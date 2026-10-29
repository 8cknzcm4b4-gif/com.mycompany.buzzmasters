import 'package:buzz_masters/bm/monetisation/models.dart';
import 'package:buzz_masters/bm/monetisation/rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 29, 12);

  group('VIP entitlement gate', () {
    const verified = VipEntitlement(
      isActive: true,
      source: EntitlementSource.storeVerified,
      productId: ProductIds.vipMonthly,
      willRenew: true,
    );

    test('a store-verified entitlement inside its period grants VIP', () {
      final entitlement = VipEntitlement(
        isActive: true,
        source: EntitlementSource.storeVerified,
        productId: ProductIds.vipMonthly,
        expiresAt: now.add(const Duration(days: 20)),
      );
      expect(vipAccessAt(entitlement, now), isTrue);
    });

    test('an expired entitlement does not grant VIP', () {
      final entitlement = VipEntitlement(
        isActive: true,
        source: EntitlementSource.storeVerified,
        expiresAt: now.subtract(const Duration(minutes: 1)),
      );
      expect(vipAccessAt(entitlement, now), isFalse);
    });

    test('a locally-flipped flag without store verification grants nothing', () {
      // isActive true but the source is not the store: the shape a naive
      // local boolean implementation would produce.
      const entitlement = VipEntitlement(
        isActive: true,
        source: EntitlementSource.validationFailed,
      );
      expect(entitlement.isVerified, isFalse);
      expect(vipAccessAt(entitlement, now), isFalse);
    });

    test('an unconfigured store never grants VIP', () {
      const entitlement = VipEntitlement(
        isActive: true,
        source: EntitlementSource.storeNotConfigured,
      );
      expect(vipAccessAt(entitlement, now), isFalse);
    });

    test('a cancelled-but-still-paid subscription stays live until expiry', () {
      final entitlement = VipEntitlement(
        isActive: true,
        source: EntitlementSource.storeVerified,
        willRenew: false,
        expiresAt: now.add(const Duration(days: 5)),
      );
      expect(vipAccessAt(entitlement, now), isTrue);
      expect(vipAccessAt(entitlement, now.add(const Duration(days: 6))),
          isFalse);
    });

    test('VIP never disables ordinary game access rules', () {
      // VIP only controls advertising; it is not part of the race rules.
      expect(showOrdinaryAdsAt(verified, now), isFalse);
      expect(showOrdinaryAdsAt(const VipEntitlement.none(), now), isTrue);
    });
  });

  group('Rewarded advert caps', () {
    const policy = AdRewardPolicy(coinsPerReward: 50, maxPerUtcDay: 5);
    final day = utcDayOf(now);

    test('a verified event grants the configured coins', () {
      final decision = decideAdReward(
        policy: policy,
        utcDay: day,
        usedToday: 0,
        eventIdsToday: const {},
        eventId: 'evt-1',
        signatureValid: true,
      );
      expect(decision.outcome, AdRewardOutcome.granted);
      expect(decision.coins, 50);
      expect(decision.usedToday, 1);
    });

    test('an unverified callback grants nothing', () {
      final decision = decideAdReward(
        policy: policy,
        utcDay: day,
        usedToday: 0,
        eventIdsToday: const {},
        eventId: 'evt-1',
        signatureValid: false,
      );
      expect(decision.outcome, AdRewardOutcome.signatureInvalid);
      expect(decision.coins, 0);
    });

    test('a duplicate callback neither pays nor consumes a slot', () {
      final decision = decideAdReward(
        policy: policy,
        utcDay: day,
        usedToday: 3,
        eventIdsToday: const {'evt-2'},
        eventId: 'evt-2',
        signatureValid: true,
      );
      expect(decision.outcome, AdRewardOutcome.duplicate);
      expect(decision.coins, 0);
      expect(decision.usedToday, 3);
    });

    test('the fifth reward is allowed and the sixth is refused', () {
      final fifth = decideAdReward(
        policy: policy,
        utcDay: day,
        usedToday: 4,
        eventIdsToday: const {'a', 'b', 'c', 'd'},
        eventId: 'e',
        signatureValid: true,
      );
      expect(fifth.outcome, AdRewardOutcome.granted);

      final sixth = decideAdReward(
        policy: policy,
        utcDay: day,
        usedToday: 5,
        eventIdsToday: const {'a', 'b', 'c', 'd', 'e'},
        eventId: 'f',
        signatureValid: true,
      );
      expect(sixth.outcome, AdRewardOutcome.dailyCapReached);
      expect(sixth.coins, 0);
    });

    test('an empty event id is rejected', () {
      final decision = decideAdReward(
        policy: policy,
        utcDay: day,
        usedToday: 0,
        eventIdsToday: const {},
        eventId: '   ',
        signatureValid: true,
      );
      expect(decision.outcome, AdRewardOutcome.rejected);
    });

    test('an administrator edit is clamped back into a sane range', () {
      const reckless = AdRewardPolicy(coinsPerReward: 999999, maxPerUtcDay: 0);
      final sane = reckless.sanitized();
      expect(sane.coinsPerReward, lessThanOrEqualTo(1000));
      expect(sane.maxPerUtcDay, greaterThanOrEqualTo(1));
    });

    test('UTC day boundaries group rewards correctly', () {
      final lateUtc = DateTime.utc(2026, 10, 29, 23, 59, 59);
      final earlyNext = DateTime.utc(2026, 10, 30, 0, 0, 1);
      expect(utcDayOf(lateUtc), 20261029);
      expect(utcDayOf(earlyNext), 20261030);
    });
  });

  group('Wallet ledger', () {
    WalletEntry entry(String key, int delta, {int day = 20261029}) =>
        WalletEntry(
          entryId: key,
          eventKey: key,
          delta: delta,
          reason: WalletReason.adReward,
          occurredAtDay: day,
        );

    test('replaying the same key does not double-credit', () {
      var ledger = const WalletLedger();
      ledger = applyWalletEntry(ledger, entry('evt-1', 50));
      ledger = applyWalletEntry(ledger, entry('evt-1', 50));
      expect(ledger.balance, 50);
      expect(ledger.entries, hasLength(1));
    });

    test('distinct events accumulate', () {
      var ledger = const WalletLedger();
      ledger = applyWalletEntry(ledger, entry('evt-1', 50));
      ledger = applyWalletEntry(ledger, entry('evt-2', 50));
      expect(ledger.balance, 100);
    });

    test('the balance never goes negative', () {
      var ledger = const WalletLedger();
      ledger = applyWalletEntry(ledger, entry('buy', -1000));
      expect(ledger.balance, 0);
      expect(ledger.entries, isEmpty);
    });

    test('ad rewards used today counts only that reason and day', () {
      var ledger = const WalletLedger();
      ledger = applyWalletEntry(ledger, entry('evt-1', 50));
      ledger = applyWalletEntry(ledger, entry('evt-2', 50, day: 20261030));
      ledger = applyWalletEntry(
        ledger,
        const WalletEntry(
          entryId: 'daily',
          eventKey: 'daily',
          delta: 50,
          reason: WalletReason.dailyReward,
          occurredAtDay: 20261029,
        ),
      );
      expect(adRewardsUsedOn(ledger, 20261029), 1);
      expect(adEventIdsOn(ledger, 20261029), {'evt-1'});
    });
  });

  group('Inventory', () {
    const start = InventorySnapshot();

    test('granting is idempotent', () {
      var inventory = grantItems(start, const ['frame_aurora']);
      inventory = grantItems(inventory, const ['frame_aurora']);
      expect(inventory.ownedItemIds, {'frame_aurora'});
    });

    test('an item the player does not own cannot be equipped', () {
      final inventory = equipItem(
        start,
        ShopCategory.profileFrames,
        'frame_aurora',
      );
      expect(inventory.equipped, isEmpty);
    });

    test('an owned item equips and then unequips', () {
      var inventory = grantItems(start, const ['frame_aurora']);
      inventory = equipItem(inventory, ShopCategory.profileFrames, 'frame_aurora');
      expect(inventory.equipped[ShopCategory.profileFrames], 'frame_aurora');
      inventory = unequipItem(inventory, ShopCategory.profileFrames);
      expect(inventory.equipped.containsKey(ShopCategory.profileFrames), isFalse);
    });

    test('equipping replaces the item in the same slot only', () {
      var inventory =
          grantItems(start, const ['frame_aurora', 'trail_neon']);
      inventory = equipItem(inventory, ShopCategory.profileFrames, 'frame_aurora');
      inventory = equipItem(inventory, ShopCategory.racingTrails, 'trail_neon');
      expect(inventory.equipped, hasLength(2));
    });
  });

  group('Purchase eligibility', () {
    const vipOnlyItem = ShopItem(
      id: 'vip_frame_royal',
      name: 'Royal VIP Frame',
      category: ShopCategory.vipExclusive,
      description: '',
      vipOnly: true,
    );
    const bundle = ShopItem(
      id: 'bundle_starter',
      name: 'Starter Bundle',
      category: ShopCategory.bundles,
      description: '',
      bundleProductIds: [ProductIds.starterBundle],
      grantsItemIds: ['frame_aurora'],
    );
    const price = StoreProduct(
      productId: ProductIds.starterBundle,
      title: 'Starter',
      priceString: '£1.99',
      currencyCode: 'GBP',
      kind: StoreProductKind.nonConsumable,
    );

    const activeVip = VipEntitlement(
      isActive: true,
      source: EntitlementSource.storeVerified,
    );

    test('a VIP-only cosmetic is blocked for a non-member', () {
      expect(
        purchaseBlockReason(
          item: vipOnlyItem,
          product: null,
          entitlement: const VipEntitlement.none(),
          now: now,
        ),
        isNotNull,
      );
    });

    test('a VIP-only cosmetic is allowed for a member', () {
      expect(
        purchaseBlockReason(
          item: vipOnlyItem,
          product: null,
          entitlement: activeVip,
          now: now,
        ),
        isNull,
      );
    });

    test('a product the store does not list cannot be bought', () {
      expect(
        purchaseBlockReason(
          item: bundle,
          product: null,
          entitlement: const VipEntitlement.none(),
          now: now,
        ),
        isNotNull,
      );
    });

    test('a product without a store price cannot be bought', () {
      const noPrice = StoreProduct(
        productId: ProductIds.starterBundle,
        title: 'Starter',
        priceString: '',
        currencyCode: 'GBP',
        kind: StoreProductKind.nonConsumable,
      );
      expect(
        purchaseBlockReason(
          item: bundle,
          product: noPrice,
          entitlement: const VipEntitlement.none(),
          now: now,
        ),
        isNotNull,
      );
    });

    test('an unknown product id resolves to nothing', () {
      expect(resolveProduct(const [], 'nope'), isNull);
      expect(resolveProduct(const [price], ProductIds.starterBundle), isNotNull);
    });

    test('bundle grants map to their listed contents', () {
      final granted = itemsGrantedBy(ProductIds.starterBundle, const [bundle]);
      expect(granted, containsAll(['bundle_starter', 'frame_aurora']));
    });
  });

  group('Sponsored tournaments', () {
    Tournament tournament({
      bool freeEntryOnly = true,
      TournamentStatus status = TournamentStatus.published,
    }) =>
        Tournament(
          id: 't1',
          name: 'Neon Cup',
          sponsor: const Sponsor(businessName: 'Acme Racing'),
          startsAt: now.subtract(const Duration(days: 1)),
          endsAt: now.add(const Duration(days: 6)),
          entryRule: 'Free entry',
          prizes: const ['Cosmetic bundle'],
          status: status,
          freeEntryOnly: freeEntryOnly,
        );

    test('free entry is allowed', () {
      expect(
        tournamentEntryBlock(
          tournament: tournament(),
          alreadyJoined: false,
          now: now,
        ),
        isNull,
      );
    });

    test('a paid-entry tournament is never joinable', () {
      expect(
        tournamentEntryBlock(
          tournament: tournament(freeEntryOnly: false),
          alreadyJoined: false,
          now: now,
        ),
        isNotNull,
      );
    });

    test('entering twice is refused', () {
      expect(
        tournamentEntryBlock(
          tournament: tournament(),
          alreadyJoined: true,
          now: now,
        ),
        isNotNull,
      );
    });

    test('a draft tournament cannot be entered', () {
      expect(
        tournamentEntryBlock(
          tournament: tournament(status: TournamentStatus.draft),
          alreadyJoined: false,
          now: now,
        ),
        isNotNull,
      );
    });

    test('ranking is deterministic: correct first, then tie-break, then id', () {
      final ranked = rankTournament(const [
        TournamentScore(playerId: 'bob', correct: 5, tiedBreakMs: 900),
        TournamentScore(playerId: 'ana', correct: 5, tiedBreakMs: 400),
        TournamentScore(playerId: 'cid', correct: 2, tiedBreakMs: 100),
        TournamentScore(playerId: 'zoe', correct: 5, tiedBreakMs: 400),
      ]);
      expect(
        ranked.map((s) => s.playerId).toList(),
        ['ana', 'zoe', 'bob', 'cid'],
      );
      expect(tournamentPosition(ranked, 'bob'), 3);
      expect(tournamentPosition(ranked, 'nobody'), isNull);
    });

    test('sponsor disclosure label is always present', () {
      expect(tournament().sponsoredLabel, 'Sponsored');
    });
  });

  group('Revenue reporting', () {
    test('a missing source keeps the total unconnected, never £0', () {
      final sum = sumMoney(const [
        MoneyStream(amountPence: 1000),
        MoneyStream.notConnected(),
      ]);
      expect(sum.connected, isFalse);
      expect(sum.formatted, 'Not connected');
    });

    test('connected sources add up', () {
      final sum = sumMoney(const [
        MoneyStream(amountPence: 1000),
        MoneyStream(amountPence: 500),
      ]);
      expect(sum.formatted, '£15.00');
    });

    test('net is withheld unless every input exists', () {
      final net = netOf(
        gross: const MoneyStream(amountPence: 10000),
        fees: const MoneyStream(amountPence: 1500),
        refunds: const MoneyStream.notConnected(),
        taxEstimate: const MoneyStream(amountPence: 0),
      );
      expect(net.connected, isFalse);
    });

    test('net subtracts fees, refunds and tax when all are known', () {
      final net = netOf(
        gross: const MoneyStream(amountPence: 10000),
        fees: const MoneyStream(amountPence: 1500),
        refunds: const MoneyStream(amountPence: 500),
        taxEstimate: const MoneyStream(amountPence: 2000),
      );
      expect(net.formatted, '£60.00');
    });

    test('the not-connected summary never claims a revenue figure', () {
      const summary = AdminRevenueSummary.notConnected();
      expect(summary.vipMrr.connected, isFalse);
      expect(summary.gross.formatted, 'Not connected');
      expect(summary.net.formatted, 'Not connected');
    });
  });

  group('Game account identity', () {
    test('an unresolved account is not usable', () {
      expect(BmGameAccount.pending.isUsable, isFalse);
    });

    test('a generated account id is usable', () {
      expect(const BmGameAccount('acct_0123456789abcdef').isUsable, isTrue);
    });
  });
}
