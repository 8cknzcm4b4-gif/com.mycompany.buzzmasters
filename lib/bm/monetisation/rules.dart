/// Pure decision logic for Buzz Masters monetisation.
///
/// Everything here is deterministic and side-effect free so it can be unit
/// tested without a store, a network or a database. The rules that protect
/// money — entitlement gates, reward caps, idempotency, non-negative balances,
/// free-entry tournaments — live here and nowhere else.
library;

import 'models.dart';

/// UTC calendar day as `yyyymmdd`, the unit every daily cap is counted in.
int utcDayOf(DateTime moment) => moment.toUtc().year * 10000 +
    moment.toUtc().month * 100 +
    moment.toUtc().day;

/// VIP gating. A local flag can never open this door: the entitlement must
/// have come from the store and must still be inside its paid period.
bool vipAccessAt(VipEntitlement entitlement, DateTime now) =>
    entitlement.isLiveAt(now);

/// Whether ordinary, non-rewarded advertising should be shown.
///
/// VIP removes ordinary ads; rewarded ads stay available to everyone who
/// voluntarily opts in (including VIP players).
bool showOrdinaryAdsAt(VipEntitlement entitlement, DateTime now) =>
    !vipAccessAt(entitlement, now);

// ---------------------------------------------------------------------------
// Rewarded ads
// ---------------------------------------------------------------------------

/// Decides whether one verified advert callback may grant coins.
///
/// [eventIdsToday] are the ad event ids already credited for [utcDay] — used
/// to deduplicate repeated callbacks (double fires, retries, replayed
/// signatures). The cap counts *distinct accepted events*, so a duplicate can
/// never consume a slot nor pay twice.
AdRewardDecision decideAdReward({
  required AdRewardPolicy policy,
  required int utcDay,
  required int usedToday,
  required Set<String> eventIdsToday,
  required String eventId,
  required bool signatureValid,
}) {
  if (!signatureValid) {
    return const AdRewardDecision(AdRewardOutcome.signatureInvalid);
  }
  if (eventId.trim().isEmpty) {
    return const AdRewardDecision(AdRewardOutcome.rejected);
  }
  if (eventIdsToday.contains(eventId)) {
    return AdRewardDecision(AdRewardOutcome.duplicate, usedToday: usedToday);
  }
  final sanitized = policy.sanitized();
  if (usedToday >= sanitized.maxPerUtcDay) {
    return AdRewardDecision(
      AdRewardOutcome.dailyCapReached,
      usedToday: usedToday,
    );
  }
  return AdRewardDecision(
    AdRewardOutcome.granted,
    coins: sanitized.coinsPerReward,
    usedToday: usedToday + 1,
  );
}

// ---------------------------------------------------------------------------
// Wallet
// ---------------------------------------------------------------------------

/// Applies one entry to a ledger.
///
/// Idempotent on [WalletEntry.eventKey]: replaying the same key returns the
/// ledger untouched. Coins can never drop below zero, and entries are kept in
/// a stable order so two devices converge on the same balance.
WalletLedger applyWalletEntry(WalletLedger ledger, WalletEntry entry) {
  if (entry.eventKey.isNotEmpty &&
      ledger.entries.any((e) => e.eventKey == entry.eventKey)) {
    return ledger;
  }
  if (entry.delta <= 0 && ledger.balance + entry.delta < 0) {
    return ledger;
  }
  final entries = [...ledger.entries, entry];
  var balance = 0;
  for (final e in entries) {
    balance += e.delta;
  }
  return WalletLedger(entries: entries, balance: balance < 0 ? 0 : balance);
}

/// Sum of ad-reward credits already recorded for a UTC day.
int adRewardsUsedOn(WalletLedger ledger, int utcDay) => ledger.entries
    .where((e) => e.reason == WalletReason.adReward && e.occurredAtDay == utcDay)
    .length;

/// Ad event ids already credited for a UTC day.
Set<String> adEventIdsOn(WalletLedger ledger, int utcDay) => {
      for (final e in ledger.entries)
        if (e.reason == WalletReason.adReward &&
            e.occurredAtDay == utcDay &&
            e.eventKey.isNotEmpty)
          e.eventKey,
    };

// ---------------------------------------------------------------------------
// Inventory
// ---------------------------------------------------------------------------

/// Grants items to an inventory. Idempotent: owning an item twice is
/// impossible, so a replayed purchase confirmation cannot duplicate stock.
InventorySnapshot grantItems(InventorySnapshot inventory, Iterable<String> ids) {
  final owned = {...inventory.ownedItemIds};
  var added = false;
  for (final id in ids) {
    if (owned.add(id)) added = true;
  }
  if (!added) return inventory;
  return inventory.copyWith(ownedItemIds: owned);
}

/// Equips a cosmetic, but only if the player owns it. Returns the inventory
/// unchanged when they do not.
InventorySnapshot equipItem(
  InventorySnapshot inventory,
  ShopCategory category,
  String itemId,
) {
  if (!inventory.owns(itemId)) return inventory;
  final equipped = {...inventory.equipped, category: itemId};
  return inventory.copyWith(equipped: equipped);
}

/// Unequips a slot.
InventorySnapshot unequipItem(InventorySnapshot inventory, ShopCategory category) {
  final equipped = {...inventory.equipped}..remove(category);
  return inventory.copyWith(equipped: equipped);
}

// ---------------------------------------------------------------------------
// Purchases
// ---------------------------------------------------------------------------

/// Resolves a product id against the store's catalogue. A missing product is
/// an error, never a silent success and never a guessed price.
StoreProduct? resolveProduct(List<StoreProduct> catalogue, String productId) {
  for (final p in catalogue) {
    if (p.productId == productId) return p;
  }
  return null;
}

/// Which items a product unlocks, given the catalogue.
List<String> itemsGrantedBy(String productId, List<ShopItem> catalog) {
  final granted = <String>[];
  for (final item in catalog) {
    if (item.bundleProductIds.contains(productId)) {
      granted.addAll(item.grantsItemIds);
      granted.add(item.id);
    }
  }
  return granted.toSet().toList();
}

/// Purchase eligibility: VIP-only cosmetics need a live VIP entitlement, and
/// a product the store does not list can never be bought.
String? purchaseBlockReason({
  required ShopItem item,
  required StoreProduct? product,
  required VipEntitlement entitlement,
  required DateTime now,
}) {
  if (item.vipOnly && !vipAccessAt(entitlement, now)) {
    return 'VIP members only.';
  }
  if (item.isBundle) {
    if (product == null) return 'This product is not available on your store.';
    if (!product.hasPrice) return 'Price unavailable from the store.';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Sponsored tournaments
// ---------------------------------------------------------------------------

/// Free entry only. A tournament that charges, wagers or requires a
/// subscription is never joinable in this build.
String? tournamentEntryBlock({
  required Tournament tournament,
  required bool alreadyJoined,
  required DateTime now,
}) {
  if (!tournament.freeEntryOnly) {
    return 'Paid entry tournaments are not supported.';
  }
  if (alreadyJoined) return 'You are already entered.';
  if (tournament.status == TournamentStatus.draft ||
      tournament.status == TournamentStatus.closed ||
      tournament.status == TournamentStatus.archived) {
    return 'This tournament is not open for entry.';
  }
  if (now.isBefore(tournament.startsAt)) return 'Entry has not opened yet.';
  if (now.isAfter(tournament.endsAt)) return 'Entry has closed.';
  return null;
}

/// Deterministic ranking: most correct first, then the faster tie-break time,
/// then the player id so two devices always agree.
List<TournamentScore> rankTournament(List<TournamentScore> scores) {
  final sorted = [...scores]..sort((a, b) {
      if (a.correct != b.correct) return b.correct.compareTo(a.correct);
      if (a.tiedBreakMs != b.tiedBreakMs) {
        return a.tiedBreakMs.compareTo(b.tiedBreakMs);
      }
      return a.playerId.compareTo(b.playerId);
    });
  return sorted;
}

/// 1-based placement, or null when the player is not in the list.
int? tournamentPosition(List<TournamentScore> ranked, String playerId) {
  for (var i = 0; i < ranked.length; i++) {
    if (ranked[i].playerId == playerId) return i + 1;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Admin revenue
// ---------------------------------------------------------------------------

/// Adds the connected channels together. A missing source keeps the total
/// unconnected rather than silently contributing £0.
MoneyStream sumMoney(List<MoneyStream> parts) {
  if (parts.any((p) => !p.connected)) return const MoneyStream.notConnected();
  var total = 0;
  for (final p in parts) {
    total += p.amountPence!;
  }
  return MoneyStream(amountPence: total);
}

/// Net = gross − fees − refunds − tax estimate, only when every input exists.
MoneyStream netOf({
  required MoneyStream gross,
  required MoneyStream fees,
  required MoneyStream refunds,
  required MoneyStream taxEstimate,
}) {
  if (!gross.connected ||
      !fees.connected ||
      !refunds.connected ||
      !taxEstimate.connected) {
    return const MoneyStream.notConnected();
  }
  return MoneyStream(
    amountPence:
        gross.amountPence! - fees.amountPence! - refunds.amountPence! - taxEstimate.amountPence!,
  );
}

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

/// The account a purchase is attached to.
///
/// The app has no sign-in yet, so this is the stable game account stored on
/// device. It is the single value handed to RevenueCat as the app user id —
/// one id per player across devices, never a per-install random value, so
/// restores and cross-device entitlement work once real auth lands.
class BmGameAccount {
  const BmGameAccount(this.id);

  final String id;

  bool get isUsable => id.trim().length >= 8;

  static const pending = BmGameAccount('');
}
