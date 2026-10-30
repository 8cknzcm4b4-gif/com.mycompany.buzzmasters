/// In-memory doubles for the monetisation gateways.
///
/// These let the tests exercise the real controller and rules without a store,
/// an ad network or a database. Nothing here can grant anything the production
/// code would not grant — they only supply the responses.
library;

import 'package:buzz_masters/bm/monetisation/controller.dart';
import 'package:buzz_masters/bm/monetisation/gateways.dart';
import 'package:buzz_masters/bm/monetisation/models.dart';
import 'package:buzz_masters/bm/monetisation/rules.dart';

class FakeStore implements StoreGateway {
  FakeStore({
    this.configured = true,
    Map<String, VipEntitlement>? entitlements,
    this.failPurchaseWith,
    this.cancelPurchase = false,
    List<StoreProduct>? catalogue,
  })  : _entitlements = entitlements ?? {},
        _catalogue = catalogue ?? _defaultCatalogue;

  final bool configured;
  final Map<String, VipEntitlement> _entitlements;
  final List<StoreProduct> _catalogue;
  final String? failPurchaseWith;
  final bool cancelPurchase;

  final List<String> purchased = <String>[];
  bool restored = false;
  bool manageOpened = false;

  static const _defaultCatalogue = <StoreProduct>[
    StoreProduct(
      productId: 'buzzmasters_vip_monthly',
      title: 'VIP Monthly',
      priceString: '£3.99',
      currencyCode: 'GBP',
      kind: StoreProductKind.subscription,
      vipPeriod: VipPeriod.monthly,
    ),
    StoreProduct(
      productId: 'buzzmasters_vip_annual',
      title: 'VIP Annual',
      priceString: '£29.99',
      currencyCode: 'GBP',
      kind: StoreProductKind.subscription,
      vipPeriod: VipPeriod.annual,
    ),
    StoreProduct(
      productId: 'buzzmasters_starter_bundle',
      title: 'Starter Bundle',
      priceString: '£1.99',
      currencyCode: 'GBP',
      kind: StoreProductKind.nonConsumable,
    ),
    StoreProduct(
      productId: 'buzzmasters_neon_bundle',
      title: 'Neon Bundle',
      priceString: '£4.99',
      currencyCode: 'GBP',
      kind: StoreProductKind.nonConsumable,
    ),
    StoreProduct(
      productId: 'buzzmasters_legendary_bundle',
      title: 'Legendary Bundle',
      priceString: '£9.99',
      currencyCode: 'GBP',
      kind: StoreProductKind.nonConsumable,
    ),
  ];

  @override
  bool get isConfigured => configured;

  /// Grants/revokes VIP for an account — the store is the only source.
  void setEntitlement(String accountId, VipEntitlement entitlement) =>
      _entitlements[accountId] = entitlement;

  @override
  Future<List<StoreProduct>> products(List<String> productIds) async =>
      configured
          ? [
              for (final p in _catalogue)
                if (productIds.contains(p.productId)) p,
            ]
          : const [];

  @override
  Future<PurchaseResult> purchase(String productId) async {
    if (!configured) {
      return const PurchaseResult.failure('The store is not connected.');
    }
    if (failPurchaseWith != null) {
      return PurchaseResult.failure(failPurchaseWith!);
    }
    if (cancelPurchase) return const PurchaseResult.cancelled();
    if (_catalogue.every((p) => p.productId != productId)) {
      return const PurchaseResult.failure(
          'This product is not available on your store.');
    }
    purchased.add(productId);
    return PurchaseResult(state: PurchaseState.success, productId: productId);
  }

  @override
  Future<PurchaseResult> restore() async {
    if (!configured) {
      return const PurchaseResult.failure('The store is not connected.');
    }
    restored = true;
    return const PurchaseResult(state: PurchaseState.restored);
  }

  @override
  Future<VipEntitlement> entitlement(String appUserId) async {
    if (!configured) {
      return const VipEntitlement(
        isActive: false,
        source: EntitlementSource.storeNotConfigured,
      );
    }
    return _entitlements[appUserId] ?? const VipEntitlement.none();
  }

  @override
  Future<List<PurchaseRecord>> history() async => const [];

  @override
  Future<bool> openManageSubscription() async {
    manageOpened = true;
    return configured;
  }
}

/// Backend that owns state per account, so a "logout/login" is just a new
/// controller pointed at the same instance.
class FakeBackend implements MonetisationBackend {
  FakeBackend({this.configured = true, this.rejectPurchases = false});

  final bool configured;
  bool rejectPurchases;

  final Map<String, InventorySnapshot> inventoryByAccount = {};
  final Map<String, WalletLedger> walletByAccount = {};
  final Map<String, List<PurchaseRecord>> historyByAccount = {};
  final Map<String, Set<String>> creditedEvents = {};
  final Map<String, Set<int>> dailyRewardDays = {};
  final Map<String, Set<String>> tournamentMembers = {};
  final List<Tournament> tournamentList = [];

  /// When set, join attempts for this tournament id fail — used to prove an
  /// unauthorised modification is refused.
  String? refuseTournamentId;

  bool adminAuthorized = false;

  InventorySnapshot _inv(String id) =>
      inventoryByAccount[id] ?? const InventorySnapshot();

  WalletLedger _wallet(String id) =>
      walletByAccount[id] ?? const WalletLedger();

  @override
  bool get isConfigured => configured;

  @override
  Future<VipEntitlement> fetchEntitlement(String accountId) async =>
      const VipEntitlement.none();

  @override
  Future<InventorySnapshot> fetchInventory(String accountId) async =>
      _inv(accountId);

  @override
  Future<WalletLedger> fetchWallet(String accountId) async =>
      _wallet(accountId);

  @override
  Future<PurchaseSyncResult> recordPurchase({
    required String accountId,
    required String transactionId,
    required String productId,
    required String priceString,
    required bool revoked,
  }) async {
    if (!configured || rejectPurchases) {
      return const PurchaseSyncResult(
        accepted: false,
        message: 'Backend is not configured — ownership cannot be recorded.',
      );
    }
    final key = '$accountId:$transactionId';
    final duplicate =
        creditedEvents.putIfAbsent('purchases', () => {}).contains(key);
    if (!duplicate) creditedEvents['purchases']!.add(key);

    if (revoked) {
      return PurchaseSyncResult(accepted: true, duplicate: duplicate);
    }

    final granted = itemsGrantedBy(productId, ShopCatalog.items);
    final inventory = grantItems(_inv(accountId), granted);
    inventoryByAccount[accountId] = inventory;
    historyByAccount.putIfAbsent(accountId, () => []).add(PurchaseRecord(
          transactionId: transactionId,
          productId: productId,
          purchasedAt: DateTime.now(),
          priceString: priceString,
        ));
    return PurchaseSyncResult(
      accepted: true,
      grantedItemIds: granted,
      duplicate: duplicate,
      message: duplicate ? 'Already owned.' : '',
    );
  }

  @override
  Future<List<PurchaseRecord>> purchaseHistory(String accountId) async =>
      historyByAccount[accountId] ?? const [];

  @override
  Future<AdRewardDecision> grantAdReward({
    required String accountId,
    required String eventId,
    required int utcDay,
    required bool signatureValid,
    required AdRewardPolicy policy,
  }) async {
    if (!configured) {
      return const AdRewardDecision(AdRewardOutcome.rejected);
    }
    final credited = creditedEvents.putIfAbsent(accountId, () => {});
    final decision = decideAdReward(
      policy: policy,
      utcDay: utcDay,
      usedToday: credited.length,
      eventIdsToday: credited,
      eventId: eventId,
      signatureValid: signatureValid,
    );
    if (decision.granted) {
      credited.add(eventId);
      walletByAccount[accountId] = applyWalletEntry(
        _wallet(accountId),
        WalletEntry(
          entryId: eventId,
          eventKey: eventId,
          delta: decision.coins,
          reason: WalletReason.adReward,
          occurredAtDay: utcDay,
        ),
      );
    }
    return decision;
  }

  @override
  Future<AdRewardDecision> claimDailyReward({
    required String accountId,
    required int utcDay,
  }) async {
    if (!configured) return const AdRewardDecision(AdRewardOutcome.rejected);
    final days = dailyRewardDays.putIfAbsent(accountId, () => {});
    if (!days.add(utcDay)) {
      return const AdRewardDecision(AdRewardOutcome.duplicate);
    }
    walletByAccount[accountId] = applyWalletEntry(
      _wallet(accountId),
      WalletEntry(
        entryId: 'daily:$utcDay',
        eventKey: 'daily:$utcDay',
        delta: 50,
        reason: WalletReason.dailyReward,
        occurredAtDay: utcDay,
      ),
    );
    return const AdRewardDecision(AdRewardOutcome.granted, coins: 50);
  }

  @override
  Future<void> syncEquipped({
    required String accountId,
    required ShopCategory category,
    required String itemId,
  }) async {}

  @override
  Future<List<Tournament>> tournaments() async => tournamentList;

  @override
  Future<String?> joinTournament({
    required String accountId,
    required String tournamentId,
  }) async {
    if (!configured) return 'Backend is not configured.';
    if (refuseTournamentId == tournamentId) {
      return 'Entry was refused by the server.';
    }
    if (!tournamentMembers.putIfAbsent(tournamentId, () => {}).add(accountId)) {
      return 'Already entered.';
    }
    return null;
  }

  @override
  Future<List<TournamentScore>> standings(String tournamentId) async =>
      const [];

  @override
  Future<AdminRevenueSummary> adminSummary() async => adminAuthorized
      ? const AdminRevenueSummary.notConnected()
      : const AdminRevenueSummary.notConnected();
}

class FakeAds implements AdsGateway {
  FakeAds({this.configured = true, this.ready = true, this.result});

  final bool configured;
  bool ready;
  AdWatchResult? result;

  int loadCalls = 0;

  @override
  bool get isConfigured => configured;

  @override
  bool get isRewardedReady => ready;

  @override
  Future<bool> loadRewarded() async {
    loadCalls++;
    return configured && ready;
  }

  @override
  Future<AdWatchResult> showRewarded() async =>
      result ?? const AdWatchResult.dismissed();
}
