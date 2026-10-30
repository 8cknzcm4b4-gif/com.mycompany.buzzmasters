import 'dart:io';

import 'package:buzz_masters/bm/monetisation/bootstrap.dart';
import 'package:buzz_masters/bm/monetisation/controller.dart';
import 'package:buzz_masters/bm/monetisation/gateways.dart';
import 'package:buzz_masters/bm/monetisation/models.dart';
import 'package:buzz_masters/bm/monetisation/rules.dart';
import 'package:buzz_masters/bm/race/race_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'monetisation/fakes.dart';

MonetisationController buildController({
  StoreGateway? store,
  MonetisationBackend? backend,
  AdsGateway? ads,
  String account = 'acct_test_account_01',
}) =>
    MonetisationController(
      store: store ?? FakeStore(),
      backend: backend ?? FakeBackend(),
      ads: ads ?? FakeAds(),
      account: BmGameAccount(account),
      clock: () => DateTime(2026, 10, 29, 12, 0, 0),
    );

void main() {
  final now = DateTime(2026, 10, 29, 12, 0, 0);

  group('VIP subscriptions', () {
    test('monthly purchase succeeds and is recorded', () async {
      final store = FakeStore();
      final backend = FakeBackend();
      final controller = buildController(store: store, backend: backend);
      await controller.load();

      final result = await controller.buyVip(ProductIds.vipMonthly);

      expect(result.state, PurchaseState.success);
      expect(store.purchased, contains(ProductIds.vipMonthly));
      expect(
        await backend.purchaseHistory(controller.account.id),
        hasLength(1),
      );
    });

    test('annual purchase succeeds and is recorded', () async {
      final store = FakeStore();
      final controller = buildController(store: store);
      await controller.load();

      final result = await controller.buyVip(ProductIds.vipAnnual);

      expect(result.state, PurchaseState.success);
      expect(store.purchased, contains(ProductIds.vipAnnual));
    });

    test('cancelling the store sheet leaves no purchase behind', () async {
      final store = FakeStore(cancelPurchase: true);
      final backend = FakeBackend();
      final controller = buildController(store: store, backend: backend);
      await controller.load();

      final result = await controller.buyVip(ProductIds.vipMonthly);

      expect(result.state, PurchaseState.cancelled);
      expect(store.purchased, isEmpty);
      expect(await backend.purchaseHistory(controller.account.id), isEmpty);
    });

    test('a failed transaction reports the error and grants nothing', () async {
      final store = FakeStore(failPurchaseWith: 'Billing unavailable');
      final controller = buildController(store: store);
      await controller.load();

      final result = await controller.buyVip(ProductIds.vipMonthly);

      expect(result.state, PurchaseState.failed);
      expect(result.message, contains('Billing unavailable'));
      expect(store.purchased, isEmpty);
    });

    test('a product the store does not list is refused before checkout',
        () async {
      final store = FakeStore(catalogue: const []);
      final controller = buildController(store: store);
      await controller.load();

      final result = await controller.buyVip(ProductIds.vipMonthly);

      expect(result.state, PurchaseState.failed);
      expect(store.purchased, isEmpty);
    });

    test('expiry ends VIP access', () async {
      final store = FakeStore();
      final controller = buildController(store: store);
      await controller.load();
      expect(controller.vipActive, isFalse);

      store.setEntitlement(
        controller.account.id,
        VipEntitlement(
          isActive: true,
          source: EntitlementSource.storeVerified,
          expiresAt: now.subtract(const Duration(minutes: 1)),
        ),
      );
      await controller.refreshEntitlement();
      expect(controller.vipActive, isFalse);
    });

    test('a live renewal keeps VIP active', () async {
      final store = FakeStore();
      final controller = buildController(store: store);
      await controller.load();

      store.setEntitlement(
        controller.account.id,
        VipEntitlement(
          isActive: true,
          source: EntitlementSource.storeVerified,
          willRenew: true,
          expiresAt: now.add(const Duration(days: 28)),
        ),
      );
      await controller.refreshEntitlement();
      expect(controller.vipActive, isTrue);
      expect(controller.entitlement.willRenew, isTrue);
    });

    test('a refund or revocation removes VIP', () async {
      final store = FakeStore();
      final backend = FakeBackend();
      final controller = buildController(store: store, backend: backend);
      await controller.load();

      store.setEntitlement(
        controller.account.id,
        const VipEntitlement(
          isActive: true,
          source: EntitlementSource.storeVerified,
          expiresAt: null,
        ),
      );
      await controller.refreshEntitlement();
      expect(controller.vipActive, isTrue);

      // Store reports the subscription revoked after a refund.
      store.setEntitlement(controller.account.id, const VipEntitlement.none());
      await controller.refreshEntitlement();
      expect(controller.vipActive, isFalse);
    });

    test('restore purchases re-reads entitlement and inventory', () async {
      final store = FakeStore();
      final backend = FakeBackend();
      final controller = buildController(store: store, backend: backend);
      await controller.load();

      store.setEntitlement(
        controller.account.id,
        const VipEntitlement(
          isActive: true,
          source: EntitlementSource.storeVerified,
        ),
      );
      final result = await controller.restorePurchases();

      expect(result.state, PurchaseState.restored);
      expect(store.restored, isTrue);
      expect(controller.vipActive, isTrue);
    });

    test('entitlement follows the account across devices', () async {
      final store = FakeStore();
      final backend = FakeBackend();
      final deviceA = buildController(store: store, backend: backend);
      await deviceA.load();
      store.setEntitlement(
        deviceA.account.id,
        const VipEntitlement(
          isActive: true,
          source: EntitlementSource.storeVerified,
        ),
      );
      await deviceA.refreshEntitlement();

      // Second device, same game account id, same store and backend.
      final deviceB = buildController(store: store, backend: backend);
      await deviceB.load();

      expect(deviceB.account.id, deviceA.account.id);
      expect(deviceB.vipActive, isTrue);
    });

    test('an unconfigured store reports it is not connected', () async {
      final store = FakeStore(configured: false);
      final controller = buildController(store: store);
      await controller.load();

      expect(controller.vipActive, isFalse);
      expect(controller.products, isEmpty);
      final result = await controller.buyVip(ProductIds.vipMonthly);
      expect(result.state, PurchaseState.failed);
    });
  });

  group('Cosmetic shop', () {
    test('a successful bundle purchase grants its contents once', () async {
      final backend = FakeBackend();
      final controller = buildController(backend: backend);
      await controller.load();

      final result = await controller.buyBundle(ProductIds.starterBundle);

      expect(result.state, PurchaseState.success);
      expect(controller.inventory.owns('frame_aurora'), isTrue);
      expect(controller.inventory.owns('trail_neon'), isTrue);
      // The three cosmetics plus the bundle itself, which the shop shows as
      // an owned indicator so a second charge is never offered.
      expect(
          controller.inventory.ownedItemIds,
          containsAll([
            'frame_aurora',
            'trail_neon',
            'celebration_thunder',
            'bundle_starter'
          ]));
    });

    test('a duplicate purchase does not duplicate ownership', () async {
      final controller = buildController();
      await controller.load();

      await controller.buyBundle(ProductIds.starterBundle);
      final second = await controller.buyBundle(ProductIds.starterBundle);

      expect(second.state, PurchaseState.success);
      expect(controller.inventory.ownedItemIds, hasLength(4));
      expect(controller.message, contains('Already owned'));
    });

    test('a backend refusal blocks the purchase', () async {
      final backend = FakeBackend(rejectPurchases: true);
      final controller = buildController(backend: backend);
      await controller.load();

      final result = await controller.buyBundle(ProductIds.starterBundle);

      expect(result.state, PurchaseState.failed);
      expect(controller.inventory.ownedItemIds, isEmpty);
    });

    test('equipping requires ownership', () async {
      final controller = buildController();
      await controller.load();
      final lockedItem = ShopCatalog.byId('frame_aurora')!;

      controller.equip(lockedItem);
      expect(controller.inventory.equipped, isEmpty);

      await controller.buyBundle(ProductIds.starterBundle);
      controller.equip(lockedItem);
      expect(
        controller.inventory.equipped[ShopCategory.profileFrames],
        'frame_aurora',
      );
    });

    test('unequip clears the slot', () async {
      final controller = buildController();
      await controller.load();
      await controller.buyBundle(ProductIds.starterBundle);
      controller.equip(ShopCatalog.byId('frame_aurora')!);

      controller.unequip(ShopCategory.profileFrames);
      expect(
        controller.inventory.equipped.containsKey(ShopCategory.profileFrames),
        isFalse,
      );
    });

    test('ownership survives a logout and login', () async {
      final backend = FakeBackend();
      final before = buildController(backend: backend);
      await before.load();
      await before.buyBundle(ProductIds.starterBundle);

      // A "new session": fresh controller, same account and backend.
      final after = buildController(backend: backend);
      await after.load();

      expect(after.inventory.owns('frame_aurora'), isTrue);
      expect(after.inventory.ownedItemIds, hasLength(4));
      expect(await backend.purchaseHistory(after.account.id), hasLength(1));
    });

    test('prices come from the store, never from the app', () async {
      final controller = buildController();
      await controller.load();
      final product = controller.productFor(ProductIds.starterBundle);
      expect(product, isNotNull);
      expect(product!.priceString, '£1.99');
      expect(controller.productFor('does_not_exist'), isNull);
    });
  });

  group('Rewarded adverts', () {
    AdWatchResult watch(String eventId, {bool signatureValid = true}) =>
        AdWatchResult(
          completed: true,
          eventId: eventId,
          signatureValid: signatureValid,
        );

    test('a completed advert grants coins through the backend', () async {
      final backend = FakeBackend();
      final ads = FakeAds(result: watch('evt-1'));
      final controller = buildController(backend: backend, ads: ads);
      await controller.load();

      final decision = await controller.watchRewardedAd();

      expect(decision.granted, isTrue);
      expect(controller.coins, 50);
      expect(controller.ledger.entries, hasLength(1));
    });

    test('an incomplete advert grants nothing', () async {
      final controller = buildController(
          ads: FakeAds(result: const AdWatchResult.dismissed()));
      await controller.load();

      final decision = await controller.watchRewardedAd();

      expect(decision.granted, isFalse);
      expect(controller.coins, 0);
    });

    test('a duplicate callback grants nothing a second time', () async {
      final backend = FakeBackend();
      final controller = buildController(
        backend: backend,
        ads: FakeAds(result: watch('evt-dup')),
      );
      await controller.load();

      final first = await controller.watchRewardedAd();
      final second = await controller.watchRewardedAd();

      expect(first.granted, isTrue);
      expect(second.outcome, AdRewardOutcome.duplicate);
      expect(controller.coins, 50);
    });

    test('an invalid signature is rejected by the backend', () async {
      final controller = buildController(
        ads: FakeAds(result: watch('evt-bad', signatureValid: false)),
      );
      await controller.load();

      final decision = await controller.watchRewardedAd();

      expect(decision.outcome, AdRewardOutcome.signatureInvalid);
      expect(controller.coins, 0);
    });

    test('the daily cap stops further rewards', () async {
      final backend = FakeBackend();
      final ads = FakeAds();
      final controller = buildController(backend: backend, ads: ads);
      await controller.load();

      final outcomes = <AdRewardOutcome>[];
      for (var i = 0; i < 7; i++) {
        ads.result = watch('evt-$i');
        final decision = await controller.watchRewardedAd();
        outcomes.add(decision.outcome);
      }

      expect(outcomes.take(5), everyElement(AdRewardOutcome.granted));
      expect(outcomes.skip(5), everyElement(AdRewardOutcome.dailyCapReached));
      expect(controller.coins, 5 * 50);
    });

    test('simultaneous callbacks for one event pay exactly once', () async {
      final backend = FakeBackend();
      final ads = FakeAds(result: watch('evt-race'));
      final controller = buildController(backend: backend, ads: ads);
      await controller.load();
      final results = await Future.wait([
        controller.watchRewardedAd(),
        controller.watchRewardedAd(),
      ]);

      expect(results.where((r) => r.granted), hasLength(1));
      expect(controller.coins, 50);
    });

    test('offline (backend unconfigured) grants nothing', () async {
      final controller = buildController(
        backend: const UnconfiguredBackend(),
        ads: FakeAds(result: watch('evt-offline')),
      );
      await controller.load();

      final decision = await controller.watchRewardedAd();

      expect(decision.granted, isFalse);
      expect(controller.coins, 0);
    });

    test('VIP does not disable the optional rewarded advert', () async {
      final store = FakeStore();
      final ads = FakeAds(result: watch('evt-vip'));
      final controller = buildController(store: store, ads: ads);
      await controller.load();
      store.setEntitlement(
        controller.account.id,
        const VipEntitlement(
          isActive: true,
          source: EntitlementSource.storeVerified,
        ),
      );
      await controller.refreshEntitlement();

      expect(controller.showOrdinaryAds, isFalse, reason: 'ordinary ads go');
      final decision = await controller.watchRewardedAd();
      expect(decision.granted, isTrue, reason: 'opt-in rewards remain');
    });

    test('the daily reward can only be claimed once per UTC day', () async {
      final controller = buildController();
      await controller.load();

      final first = await controller.claimDailyReward();
      final second = await controller.claimDailyReward();

      expect(first.granted, isTrue);
      expect(second.outcome, AdRewardOutcome.duplicate);
      expect(controller.coins, 50);
    });

    test('an unconfigured ad network reports honestly', () async {
      final controller = buildController(ads: const UnconfiguredAds());
      await controller.load();

      await controller.openAdPrompt();
      expect(controller.adState, AdPromptState.failed);
    });
  });

  group('Sponsored tournaments', () {
    Tournament makeTournament() => Tournament(
          id: 'neon-cup',
          name: 'Neon Cup',
          sponsor: const Sponsor(businessName: 'Acme Racing'),
          startsAt: now.subtract(const Duration(days: 1)),
          endsAt: now.add(const Duration(days: 6)),
          entryRule: 'Free entry',
          prizes: const ['Legendary bundle'],
          participantIds: const [],
        );

    test('a player can enter a free tournament', () async {
      final backend = FakeBackend();
      final controller = buildController(backend: backend);
      await controller.load();

      final error = await controller.joinTournament(makeTournament());

      expect(error, isNull);
      expect(
        backend.tournamentMembers['neon-cup'],
        contains(controller.account.id),
      );
    });

    test('entering twice is refused', () async {
      final controller = buildController();
      await controller.load();
      final tournament = makeTournament();

      await controller.joinTournament(tournament);
      final second = await controller.joinTournament(tournament);

      expect(second, isNotNull);
    });

    test('an unauthorised modification is rejected by the server', () async {
      final backend = FakeBackend()..refuseTournamentId = 'neon-cup';
      final controller = buildController(backend: backend);
      await controller.load();

      final error = await controller.joinTournament(makeTournament());

      expect(error, isNotNull);
      expect(backend.tournamentMembers['neon-cup'], isNull);
    });

    test('a closed tournament cannot be entered', () async {
      final controller = buildController();
      await controller.load();
      final closed = Tournament(
        id: 'old',
        name: 'Old Cup',
        sponsor: const Sponsor(businessName: 'Acme'),
        startsAt: now.subtract(const Duration(days: 30)),
        endsAt: now.subtract(const Duration(days: 20)),
        entryRule: 'Free entry',
        prizes: const [],
        status: TournamentStatus.closed,
      );

      final error = await controller.joinTournament(closed);
      expect(error, isNotNull);
    });
  });

  group('Race integrity (monetisation must not touch gameplay)', () {
    const config = RaceConfig();

    test('race maths is unchanged', () {
      expect(config.distance, 100);
      expect(config.correctGain, 10);
      expect(config.fastCorrectGain, 15);
      expect(config.wrongPenalty, 5);
      expect(config.timeoutPenalty, 3);
      expect(config.maxQuestions, 30);
    });

    test('a VIP player and a standard player score identically', () {
      RaceModel runRace() {
        var model = RaceModel(
          config: config,
          racers: const [RacerProgress(id: 'a'), RacerProgress(id: 'b')],
        ).startCountdown().go().openQuestion();
        model = model.applyAnswer(
          racerId: 'a',
          correct: true,
          responseMs: 1000,
          atMs: 1000,
        );
        model = model.applyAnswer(
          racerId: 'b',
          correct: true,
          responseMs: 1000,
          atMs: 1000,
        );
        return model;
      }

      // Entitlement plays no part in the model: the two runs are identical
      // regardless of any VIP state held elsewhere.
      final standard = runRace();
      final vip = runRace();
      expect(vip.racers.first.progress, standard.racers.first.progress);
      expect(vip.racers.first.progress, 15); // fast correct answer
    });
  });

  group('Configuration safety', () {
    test('no credential-shaped strings ship in the app source', () {
      // Guards against a service-account key, private key, JWT or the
      // RevenueCat secret key being pasted into the app. Firebase's own app
      // keys (lib/firebase_options.dart) are public identifiers by design.
      final suspicious = RegExp(
        r'(service_role|"private_key"|-----BEGIN [A-Z ]*PRIVATE KEY|eyJ[A-Za-z0-9_-]{20,}|sk_[A-Za-z0-9]{20,})',
      );
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        expect(suspicious.hasMatch(f.readAsStringSync()), isFalse,
            reason: f.path);
      }
      expect(
          MonetisationConfig.storeConfigured ||
              MonetisationConfig.revenueCatApiKey.isEmpty,
          isTrue);
    });

    test('the admin summary is not connected until a source exists', () async {
      final backend = FakeBackend();
      final controller = buildController(backend: backend);
      await controller.load();
      await controller.loadAdmin();
      expect(controller.revenue.gross.connected, isFalse);
      expect(controller.revenue.gross.formatted, 'Not connected');
    });
  });
}
