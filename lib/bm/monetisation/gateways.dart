/// Boundaries between monetisation rules and the outside world.
///
/// The controller talks only to these interfaces, so every rule can be tested
/// with an in-memory double and the production wiring (RevenueCat, AdMob,
/// Firebase) sits behind a single adapter file each.
library;

import 'models.dart';

/// What the in-app-purchase store can do.
abstract class StoreGateway {
  /// False when the SDK has no API key in this build. The UI must then say
  /// "Store not connected" instead of pretending a purchase succeeded.
  bool get isConfigured;

  /// Store catalogue for the given ids. Products the store does not list are
  /// simply absent — never invented.
  Future<List<StoreProduct>> products(List<String> productIds);

  /// Starts a purchase. Implementations resolve to [PurchaseState.cancelled]
  /// when the player dismisses the store sheet.
  Future<PurchaseResult> purchase(String productId);

  /// Restores previously bought non-consumables and subscriptions.
  Future<PurchaseResult> restore();

  /// Current store-verified VIP entitlement for [appUserId].
  Future<VipEntitlement> entitlement(String appUserId);

  /// Transaction history as the store knows it.
  Future<List<PurchaseRecord>> history();

  /// Opens the platform's subscription management screen where supported.
  Future<bool> openManageSubscription();
}

/// Rewarded advertising.
abstract class AdsGateway {
  bool get isConfigured;

  /// Preloads the next rewarded advert; resolves false when none is ready.
  Future<bool> loadRewarded();

  bool get isRewardedReady;

  /// Shows the advert. Completes with the provider's verification payload
  /// (`eventId`, `signatureValid`) — coins are NEVER granted from here; the
  /// backend decides.
  Future<AdWatchResult> showRewarded();
}

class AdWatchResult {
  const AdWatchResult({
    required this.completed,
    this.eventId = '',
    this.signatureValid = false,
    this.message = '',
  });

  const AdWatchResult.notConfigured()
      : completed = false,
        eventId = '',
        signatureValid = false,
        message = 'Advertising is not configured in this build.';

  const AdWatchResult.dismissed()
      : completed = false,
        eventId = '',
        signatureValid = false,
        message = 'Advertisement not completed — no reward granted.';

  final bool completed;
  final String eventId;
  final bool signatureValid;
  final String message;
}

/// The authoritative backend. Every mutation that touches money or ownership
/// goes through here; the client never writes a balance itself.
abstract class MonetisationBackend {
  bool get isConfigured;

  Future<VipEntitlement> fetchEntitlement(String accountId);

  Future<InventorySnapshot> fetchInventory(String accountId);

  Future<WalletLedger> fetchWallet(String accountId);

  /// Records a store transaction idempotently and returns the items it owns.
  Future<PurchaseSyncResult> recordPurchase({
    required String accountId,
    required String transactionId,
    required String productId,
    required String priceString,
    required bool revoked,
  });

  Future<List<PurchaseRecord>> purchaseHistory(String accountId);

  /// Server-side decision on one advert reward: verifies the signature,
  /// deduplicates the event id and enforces the daily cap atomically.
  Future<AdRewardDecision> grantAdReward({
    required String accountId,
    required String eventId,
    required int utcDay,
    required bool signatureValid,
    required AdRewardPolicy policy,
  });

  /// One claim per UTC day, enforced by the server.
  Future<AdRewardDecision> claimDailyReward({
    required String accountId,
    required int utcDay,
  });

  Future<void> syncEquipped({
    required String accountId,
    required ShopCategory category,
    required String itemId,
  });

  Future<List<Tournament>> tournaments();

  Future<String?> joinTournament({
    required String accountId,
    required String tournamentId,
  });

  Future<List<TournamentScore>> standings(String tournamentId);

  Future<AdminRevenueSummary> adminSummary();
}

class PurchaseSyncResult {
  const PurchaseSyncResult({
    required this.accepted,
    this.grantedItemIds = const [],
    this.duplicate = false,
    this.message = '',
  });

  final bool accepted;
  final List<String> grantedItemIds;
  final bool duplicate;
  final String message;
}

/// Backend used when Firebase is not available. It reports "not
/// connected" and empty data — it never fabricates ownership or revenue.
class UnconfiguredBackend implements MonetisationBackend {
  const UnconfiguredBackend();

  static const _emptyLedger = WalletLedger();

  @override
  bool get isConfigured => false;

  @override
  Future<VipEntitlement> fetchEntitlement(String accountId) async =>
      const VipEntitlement.none();

  @override
  Future<InventorySnapshot> fetchInventory(String accountId) async =>
      const InventorySnapshot();

  @override
  Future<WalletLedger> fetchWallet(String accountId) async => _emptyLedger;

  @override
  Future<PurchaseSyncResult> recordPurchase({
    required String accountId,
    required String transactionId,
    required String productId,
    required String priceString,
    required bool revoked,
  }) async =>
      const PurchaseSyncResult(
        accepted: false,
        message: 'Backend is not configured — ownership cannot be recorded.',
      );

  @override
  Future<List<PurchaseRecord>> purchaseHistory(String accountId) async =>
      const [];

  @override
  Future<AdRewardDecision> grantAdReward({
    required String accountId,
    required String eventId,
    required int utcDay,
    required bool signatureValid,
    required AdRewardPolicy policy,
  }) async =>
      const AdRewardDecision(AdRewardOutcome.rejected);

  @override
  Future<AdRewardDecision> claimDailyReward({
    required String accountId,
    required int utcDay,
  }) async =>
      const AdRewardDecision(AdRewardOutcome.rejected);

  @override
  Future<void> syncEquipped({
    required String accountId,
    required ShopCategory category,
    required String itemId,
  }) async {}

  @override
  Future<List<Tournament>> tournaments() async => const [];

  @override
  Future<String?> joinTournament({
    required String accountId,
    required String tournamentId,
  }) async =>
      'Backend is not configured.';

  @override
  Future<List<TournamentScore>> standings(String tournamentId) async =>
      const [];

  @override
  Future<AdminRevenueSummary> adminSummary() async =>
      const AdminRevenueSummary.notConnected();
}

/// Store used when RevenueCat has no API key. It never reports a successful
/// purchase.
class UnconfiguredStore implements StoreGateway {
  const UnconfiguredStore();

  @override
  bool get isConfigured => false;

  @override
  Future<List<StoreProduct>> products(List<String> productIds) async =>
      const [];

  @override
  Future<PurchaseResult> purchase(String productId) async =>
      const PurchaseResult.failure('The store is not connected in this build.');

  @override
  Future<PurchaseResult> restore() async =>
      const PurchaseResult.failure('The store is not connected in this build.');

  @override
  Future<VipEntitlement> entitlement(String appUserId) async =>
      const VipEntitlement.none();

  @override
  Future<List<PurchaseRecord>> history() async => const [];

  @override
  Future<bool> openManageSubscription() async => false;
}

/// Ads used when AdMob has no application id configured.
class UnconfiguredAds implements AdsGateway {
  const UnconfiguredAds();

  @override
  bool get isConfigured => false;

  @override
  Future<bool> loadRewarded() async => false;

  @override
  bool get isRewardedReady => false;

  @override
  Future<AdWatchResult> showRewarded() async =>
      const AdWatchResult.notConfigured();
}
