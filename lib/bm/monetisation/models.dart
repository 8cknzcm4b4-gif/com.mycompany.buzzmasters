/// Buzz Masters monetisation domain models.
///
/// Pure Dart: no Flutter, no network, no clock of its own. Prices are NEVER
/// hardcoded here — every price string arrives from the store, so a proposed
/// UK price in the brief is only a suggestion until the store says otherwise.
library;

// ---------------------------------------------------------------------------
// VIP
// ---------------------------------------------------------------------------

/// Billing period of a VIP subscription product.
enum VipPeriod { monthly, annual }

/// How an entitlement was established. Only [EntitlementSource.storeVerified]
/// may ever unlock VIP — a local boolean is never trusted.
enum EntitlementSource {
  /// Confirmed by the store / RevenueCat.
  storeVerified,

  /// The store SDK is not configured in this build (dev or CI).
  storeNotConfigured,

  /// The store was asked and could not confirm — treat as not entitled.
  validationFailed,
}

/// A VIP entitlement as reported by the store.
class VipEntitlement {
  const VipEntitlement({
    required this.isActive,
    required this.source,
    this.productId,
    this.expiresAt,
    this.willRenew = false,
    this.period,
    this.validatedAt,
  });

  const VipEntitlement.none()
      : isActive = false,
        source = EntitlementSource.validationFailed,
        productId = null,
        expiresAt = null,
        willRenew = false,
        period = null,
        validatedAt = null;

  final bool isActive;
  final EntitlementSource source;
  final String? productId;
  final DateTime? expiresAt;
  final bool willRenew;
  final VipPeriod? period;
  final DateTime? validatedAt;

  bool get isVerified =>
      isActive && source == EntitlementSource.storeVerified;

  /// True while the store still considers the subscription live, including
  /// Apple/Google's billing-recovery grace period.
  bool isLiveAt(DateTime now) {
    if (!isVerified) return false;
    if (expiresAt == null) return true;
    return expiresAt!.isAfter(now);
  }

  /// Human label for the membership screen.
  String get statusLabel {
    if (!isActive) return 'Not a member';
    return switch (source) {
      EntitlementSource.storeVerified =>
        willRenew ? 'Active — renews' : 'Active — cancels at period end',
      EntitlementSource.storeNotConfigured => 'Store not connected',
      EntitlementSource.validationFailed => 'Could not verify',
    };
  }
}

// ---------------------------------------------------------------------------
// Store products
// ---------------------------------------------------------------------------

enum StoreProductKind { subscription, nonConsumable }

/// A product exactly as the store reports it.
class StoreProduct {
  const StoreProduct({
    required this.productId,
    required this.title,
    required this.priceString,
    required this.currencyCode,
    required this.kind,
    this.description = '',
    this.vipPeriod,
  });

  final String productId;
  final String title;

  /// Localised, store-supplied price, e.g. `£3.99`. Empty when the store has
  /// no product with this id — the UI must then show "Unavailable", never a
  /// guessed figure.
  final String priceString;
  final String currencyCode;
  final StoreProductKind kind;
  final String description;
  final VipPeriod? vipPeriod;

  bool get hasPrice => priceString.trim().isNotEmpty;
}

/// Product ids used across iOS, Android and RevenueCat.
abstract final class ProductIds {
  static const vipMonthly = 'buzzmasters_vip_monthly';
  static const vipAnnual = 'buzzmasters_vip_annual';
  static const starterBundle = 'buzzmasters_starter_bundle';
  static const neonBundle = 'buzzmasters_neon_bundle';
  static const legendaryBundle = 'buzzmasters_legendary_bundle';

  /// The single RevenueCat entitlement both VIP products map to.
  static const vipEntitlement = 'buzzmasters_vip';

  static const vip = <String>[vipMonthly, vipAnnual];
  static const bundles = <String>[
    starterBundle,
    neonBundle,
    legendaryBundle,
  ];
  static const all = <String>[...vip, ...bundles];
}

// ---------------------------------------------------------------------------
// Cosmetics & inventory
// ---------------------------------------------------------------------------

enum ShopCategory {
  avatars,
  profileFrames,
  racingTrails,
  celebrations,
  nameplates,
  bundles,
  vipExclusive,
}

extension ShopCategoryLabel on ShopCategory {
  String get label => switch (this) {
        ShopCategory.avatars => 'AVATARS',
        ShopCategory.profileFrames => 'FRAMES',
        ShopCategory.racingTrails => 'TRAILS',
        ShopCategory.celebrations => 'CELEBRATIONS',
        ShopCategory.nameplates => 'NAMEPLATES',
        ShopCategory.bundles => 'BUNDLES',
        ShopCategory.vipExclusive => 'VIP ONLY',
      };
}

/// One purchasable or unlockable cosmetic.
class ShopItem {
  const ShopItem({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    this.bundleProductIds = const [],
    this.grantsItemIds = const [],
    this.vipOnly = false,
    this.previewIcon,
    this.previewColor = 0xFF7545EF,
  });

  final String id;
  final String name;
  final ShopCategory category;
  final String description;

  /// Store product that unlocks this item (bundles). Empty for owned-by-default
  /// cosmetics such as the VIP-exclusive set.
  final List<String> bundleProductIds;

  /// Items granted when this bundle is purchased.
  final List<String> grantsItemIds;

  final bool vipOnly;
  final int? previewIcon;
  final int previewColor;

  bool get isBundle => bundleProductIds.isNotEmpty;
}

/// What a player owns and currently wears.
class InventorySnapshot {
  const InventorySnapshot({
    this.ownedItemIds = const {},
    this.equipped = const {},
    this.coins = 0,
    this.revision = 0,
  });

  final Set<String> ownedItemIds;
  final Map<ShopCategory, String> equipped;
  final int coins;

  /// Server-monotonic version used to discard out-of-order sync responses.
  final int revision;

  bool owns(String itemId) => ownedItemIds.contains(itemId);

  InventorySnapshot copyWith({
    Set<String>? ownedItemIds,
    Map<ShopCategory, String>? equipped,
    int? coins,
    int? revision,
  }) =>
      InventorySnapshot(
        ownedItemIds: ownedItemIds ?? this.ownedItemIds,
        equipped: equipped ?? this.equipped,
        coins: coins ?? this.coins,
        revision: revision ?? this.revision,
      );
}

// ---------------------------------------------------------------------------
// Wallet
// ---------------------------------------------------------------------------

/// Why coins moved. Every ledger row carries one of these.
enum WalletReason {
  adReward,
  dailyReward,
  adminAdjustment,
  purchaseGrant,
}

class WalletEntry {
  const WalletEntry({
    required this.entryId,
    required this.delta,
    required this.reason,
    required this.occurredAtDay,
    this.eventKey = '',
  });

  /// Server-issued unique id.
  final String entryId;

  /// Deduplication key: ad event id, daily reward date, purchase transaction.
  final String eventKey;
  final int delta;
  final WalletReason reason;

  /// UTC day the credit belongs to, `yyyymmdd` — used for daily caps.
  final int occurredAtDay;
}

class WalletLedger {
  const WalletLedger({this.entries = const [], this.balance = 0});

  final List<WalletEntry> entries;
  final int balance;
}

// ---------------------------------------------------------------------------
// Rewarded ads
// ---------------------------------------------------------------------------

/// Server-side policy for rewarded adverts. Both values are administrative
/// settings; these defaults are the brief's starting point.
class AdRewardPolicy {
  const AdRewardPolicy({this.coinsPerReward = 50, this.maxPerUtcDay = 5});

  final int coinsPerReward;
  final int maxPerUtcDay;

  /// Clamp an administrator's edit back into a sane range.
  AdRewardPolicy sanitized() => AdRewardPolicy(
        coinsPerReward: coinsPerReward.clamp(1, 1000),
        maxPerUtcDay: maxPerUtcDay.clamp(1, 20),
      );
}

enum AdRewardOutcome {
  granted,
  duplicate,
  dailyCapReached,
  signatureInvalid,
  rejected,
}

class AdRewardDecision {
  const AdRewardDecision(this.outcome, {this.coins = 0, this.usedToday = 0});

  final AdRewardOutcome outcome;
  final int coins;
  final int usedToday;

  bool get granted => outcome == AdRewardOutcome.granted;
}

/// One verified advert reward, for the reward history list.
class AdRewardRecord {
  const AdRewardRecord({
    required this.eventId,
    required this.coins,
    required this.utcDay,
    required this.recordedAt,
  });

  final String eventId;
  final int coins;
  final int utcDay;
  final DateTime recordedAt;
}

// ---------------------------------------------------------------------------
// Purchases
// ---------------------------------------------------------------------------

enum PurchaseState {
  idle,
  pending,
  purchasing,
  success,
  failed,
  cancelled,
  restored,
}

class PurchaseResult {
  const PurchaseResult({
    required this.state,
    this.productId,
    this.message = '',
  });

  final PurchaseState state;
  final String? productId;
  final String message;

  const PurchaseResult.failure(String message)
      : this(state: PurchaseState.failed, message: message);

  const PurchaseResult.cancelled()
      : this(state: PurchaseState.cancelled, message: 'Purchase cancelled.');
}

class PurchaseRecord {
  const PurchaseRecord({
    required this.transactionId,
    required this.productId,
    required this.purchasedAt,
    this.state = PurchaseState.success,
    this.priceString = '',
    this.revoked = false,
  });

  final String transactionId;
  final String productId;
  final DateTime purchasedAt;
  final PurchaseState state;

  /// Store-reported price; empty when unknown (never invented).
  final String priceString;

  /// Refund / revocation reported by the store.
  final bool revoked;
}

// ---------------------------------------------------------------------------
// Sponsored tournaments
// ---------------------------------------------------------------------------

enum TournamentStatus { draft, published, live, closed, archived }

class Sponsor {
  const Sponsor({
    required this.businessName,
    this.logoAsset = '',
    this.bannerAsset = '',
    this.website = '',
  });

  final String businessName;
  final String logoAsset;
  final String bannerAsset;
  final String website;
}

class Tournament {
  const Tournament({
    required this.id,
    required this.name,
    required this.sponsor,
    required this.startsAt,
    required this.endsAt,
    required this.entryRule,
    required this.prizes,
    this.status = TournamentStatus.published,
    this.approvalState = 'pending',
    this.participantIds = const [],
    this.sponsoredLabel = 'Sponsored',
    this.freeEntryOnly = true,
  });

  final String id;
  final String name;
  final Sponsor sponsor;
  final DateTime startsAt;
  final DateTime endsAt;
  final String entryRule;
  final List<String> prizes;
  final TournamentStatus status;
  final String approvalState;
  final List<String> participantIds;

  /// Visible disclosure label — sponsored content is always marked.
  final String sponsoredLabel;

  /// Free entry only: no cash prizes, deposits or paid entry anywhere.
  final bool freeEntryOnly;

  bool isJoinableAt(DateTime now) =>
      status == TournamentStatus.published || status == TournamentStatus.live;
}

class TournamentScore {
  const TournamentScore({required this.playerId, required this.correct, this.tiedBreakMs = 0});

  final String playerId;
  final int correct;
  final int tiedBreakMs;
}

// ---------------------------------------------------------------------------
// Admin revenue
// ---------------------------------------------------------------------------

/// A revenue figure that may simply not be connected yet. `amountPence` is
/// null whenever the source is missing — the UI must print "Not connected"
/// rather than £0.
class MoneyStream {
  const MoneyStream({this.amountPence, this.currency = 'GBP'});

  const MoneyStream.notConnected() : amountPence = null, currency = 'GBP';

  final int? amountPence;
  final String currency;

  bool get connected => amountPence != null;

  String get formatted {
    if (amountPence == null) return 'Not connected';
    final pounds = amountPence! ~/ 100;
    final pence = (amountPence! % 100).toString().padLeft(2, '0');
    return '£$pounds.$pence';
  }
}

class AdminRevenueSummary {
  const AdminRevenueSummary({
    required this.vipMrr,
    required this.cosmeticGross,
    required this.adEarnings,
    required this.sponsorRevenue,
    required this.gross,
    required this.fees,
    required this.refunds,
    required this.taxEstimate,
    required this.net,
    required this.activeVipCount,
    required this.cancellations30d,
    required this.verifiedAdRewards,
    required this.outstandingErrors,
  });

  final MoneyStream vipMrr;
  final MoneyStream cosmeticGross;
  final MoneyStream adEarnings;
  final MoneyStream sponsorRevenue;
  final MoneyStream gross;
  final MoneyStream fees;
  final MoneyStream refunds;
  final MoneyStream taxEstimate;
  final MoneyStream net;
  final int activeVipCount;
  final int cancellations30d;
  final int verifiedAdRewards;
  final int outstandingErrors;

  const AdminRevenueSummary.notConnected()
      : vipMrr = const MoneyStream.notConnected(),
        cosmeticGross = const MoneyStream.notConnected(),
        adEarnings = const MoneyStream.notConnected(),
        sponsorRevenue = const MoneyStream.notConnected(),
        gross = const MoneyStream.notConnected(),
        fees = const MoneyStream.notConnected(),
        refunds = const MoneyStream.notConnected(),
        taxEstimate = const MoneyStream.notConnected(),
        net = const MoneyStream.notConnected(),
        activeVipCount = 0,
        cancellations30d = 0,
        verifiedAdRewards = 0,
        outstandingErrors = 0;
}
