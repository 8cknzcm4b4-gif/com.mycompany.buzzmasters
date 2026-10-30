/// Orchestrates VIP, shop, rewards and tournaments for the UI.
///
/// Every money-touching action calls the backend; the controller only holds
/// view state. Purchase and reward results therefore reflect what the server
/// actually accepted, never an optimistic local flip.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gateways.dart';
import 'models.dart';
import 'rules.dart';

/// Catalogue shipped with the build. Prices come from the store at runtime —
/// these strings are labels only and are replaced by real store prices when
/// the catalogue loads.
abstract final class ShopCatalog {
  static const items = <ShopItem>[
    ShopItem(
      id: 'cosmic_racer',
      name: 'Cosmic Racer',
      category: ShopCategory.avatars,
      description: 'The classic Buzz Masters pilot.',
      previewIcon: 0xe532,
    ),
    ShopItem(
      id: 'neon_phantom',
      name: 'Neon Phantom',
      category: ShopCategory.avatars,
      description: 'A glow-lit rival for night races.',
      previewIcon: 0xe80c,
    ),
    ShopItem(
      id: 'frame_rookie',
      name: 'Rookie Frame',
      category: ShopCategory.profileFrames,
      description: 'Default profile ring.',
      previewIcon: 0xe22c,
    ),
    ShopItem(
      id: 'frame_aurora',
      name: 'Aurora Frame',
      category: ShopCategory.profileFrames,
      description: 'Shifting polar-light ring for your profile.',
      previewIcon: 0xe22c,
    ),
    ShopItem(
      id: 'trail_vapor',
      name: 'Vapor Trail',
      category: ShopCategory.racingTrails,
      description: 'Default lane wake.',
      previewIcon: 0xe90b,
    ),
    ShopItem(
      id: 'trail_neon',
      name: 'Neon Slipstream',
      category: ShopCategory.racingTrails,
      description: 'Electric blue ribbon behind your racer.',
      previewIcon: 0xe90b,
    ),
    ShopItem(
      id: 'celebration_confetti',
      name: 'Confetti Burst',
      category: ShopCategory.celebrations,
      description: 'Finish-line celebration.',
      previewIcon: 0xe6d4,
    ),
    ShopItem(
      id: 'celebration_thunder',
      name: 'Thunder Finish',
      category: ShopCategory.celebrations,
      description: 'A crack of lightning when you take the win.',
      previewIcon: 0xe63a,
    ),
    ShopItem(
      id: 'nameplate_classic',
      name: 'Classic Nameplate',
      category: ShopCategory.nameplates,
      description: 'Default name strip.',
      previewIcon: 0xe0d3,
    ),
    ShopItem(
      id: 'nameplate_chrome',
      name: 'Chrome Nameplate',
      category: ShopCategory.nameplates,
      description: 'Polished metal name strip.',
      previewIcon: 0xe0d3,
    ),
    ShopItem(
      id: 'bundle_starter',
      name: 'Starter Bundle',
      category: ShopCategory.bundles,
      description: 'Aurora Frame, Neon Slipstream and Thunder Finish.',
      bundleProductIds: [ProductIds.starterBundle],
      grantsItemIds: ['frame_aurora', 'trail_neon', 'celebration_thunder'],
      previewIcon: 0xe2c7,
      previewColor: 0xFF00D8F4,
    ),
    ShopItem(
      id: 'bundle_neon',
      name: 'Neon Racing Bundle',
      category: ShopCategory.bundles,
      description: 'Neon cosmetics for your whole podium look.',
      bundleProductIds: [ProductIds.neonBundle],
      grantsItemIds: ['trail_neon', 'nameplate_chrome', 'frame_aurora'],
      previewIcon: 0xe2c7,
      previewColor: 0xFF7545EF,
    ),
    ShopItem(
      id: 'bundle_legendary',
      name: 'Legendary Cosmetic Bundle',
      category: ShopCategory.bundles,
      description: 'Every cosmetic in the current collection.',
      bundleProductIds: [ProductIds.legendaryBundle],
      grantsItemIds: [
        'frame_aurora',
        'trail_neon',
        'celebration_thunder',
        'nameplate_chrome',
        'neon_phantom',
      ],
      previewIcon: 0xe2c7,
      previewColor: 0xFFFFCB45,
    ),
    ShopItem(
      id: 'vip_frame_royal',
      name: 'Royal VIP Frame',
      category: ShopCategory.vipExclusive,
      description: 'Gold profile frame for VIP members.',
      vipOnly: true,
      previewIcon: 0xe22c,
      previewColor: 0xFFFFCB45,
    ),
    ShopItem(
      id: 'vip_trail_solar',
      name: 'Solar VIP Trail',
      category: ShopCategory.vipExclusive,
      description: 'A trail of light for VIP racers.',
      vipOnly: true,
      previewIcon: 0xe90b,
      previewColor: 0xFFFFCB45,
    ),
  ];

  static ShopItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}

/// Purchase prompt shown while a store sheet is open.
enum AdPromptState { hidden, loading, watching, failed }

class MonetisationController extends ChangeNotifier {
  MonetisationController({
    required this.store,
    required this.backend,
    required this.ads,
    required this.account,
    AdRewardPolicy policy = const AdRewardPolicy(),
    DateTime Function()? clock,
  })  : _policy = policy.sanitized(),
        _clock = clock ?? DateTime.now;

  final StoreGateway store;
  final MonetisationBackend backend;
  final AdsGateway ads;
  final BmGameAccount account;

  final AdRewardPolicy _policy;
  final DateTime Function() _clock;

  // --- view state -------------------------------------------------------
  List<StoreProduct> _products = const [];
  InventorySnapshot _inventory = const InventorySnapshot();
  WalletLedger _ledger = const WalletLedger();
  VipEntitlement _entitlement = const VipEntitlement.none();
  List<PurchaseRecord> _history = const [];
  List<Tournament> _tournaments = const [];
  AdminRevenueSummary _revenue = const AdminRevenueSummary.notConnected();
  PurchaseState _purchaseState = PurchaseState.idle;
  String _message = '';
  bool _busy = false;
  bool _loaded = false;
  AdPromptState _adState = AdPromptState.hidden;

  List<StoreProduct> get products => _products;
  InventorySnapshot get inventory => _inventory;
  WalletLedger get ledger => _ledger;
  VipEntitlement get entitlement => _entitlement;
  List<PurchaseRecord> get history => _history;
  List<Tournament> get tournaments => _tournaments;
  AdminRevenueSummary get revenue => _revenue;
  PurchaseState get purchaseState => _purchaseState;
  String get message => _message;
  bool get busy => _busy;
  bool get loaded => _loaded;
  AdPromptState get adState => _adState;
  AdRewardPolicy get policy => _policy;

  bool get vipActive => vipAccessAt(_entitlement, _clock());
  bool get showOrdinaryAds => showOrdinaryAdsAt(_entitlement, _clock());

  int get coins => _ledger.balance;
  int get adRewardsUsedToday => adRewardsUsedOn(_ledger, utcDayOf(_clock()));

  /// Products the store returned with a usable price, keyed by id.
  StoreProduct? productFor(String productId) =>
      resolveProduct(_products, productId);

  // --- loading ----------------------------------------------------------

  Future<void> load() async {
    _busy = true;
    _message = '';
    notifyListeners();
    try {
      _entitlement = await store.entitlement(account.id);
      _products = await store.products(ProductIds.all);
      _inventory = await backend.fetchInventory(account.id);
      _ledger = await backend.fetchWallet(account.id);
      _history = await backend.purchaseHistory(account.id);
      _tournaments = await backend.tournaments();
      _revenue = await backend.adminSummary();
      _loaded = true;
    } catch (error) {
      _message = 'Could not load the store: $error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshEntitlement() async {
    try {
      _entitlement = await store.entitlement(account.id);
      if (store.isConfigured) {
        _inventory = await backend.fetchInventory(account.id);
      }
    } catch (error) {
      _message = 'Could not refresh membership: $error';
    }
    notifyListeners();
  }

  // --- VIP --------------------------------------------------------------

  Future<PurchaseResult> buyVip(String productId) =>
      _runPurchase(productId, expectedKind: StoreProductKind.subscription);

  Future<PurchaseResult> buyBundle(String productId) =>
      _runPurchase(productId, expectedKind: StoreProductKind.nonConsumable);

  Future<PurchaseResult> _runPurchase(
    String productId, {
    required StoreProductKind expectedKind,
  }) async {
    final product = productFor(productId);
    if (product == null) {
      _setPurchase(const PurchaseResult.failure(
          'This product is not available on your store.'));
      return _lastPurchase!;
    }
    if (!product.hasPrice) {
      _setPurchase(const PurchaseResult.failure(
          'The store did not return a price for this product.'));
      return _lastPurchase!;
    }

    _setPurchase(
        const PurchaseResult(state: PurchaseState.purchasing, productId: null));
    final result = await store.purchase(productId);

    if (result.state == PurchaseState.success) {
      // Record with the backend so ownership is server-side and idempotent.
      final sync = await backend.recordPurchase(
        accountId: account.id,
        transactionId: result.productId ?? productId,
        productId: productId,
        priceString: product.priceString,
        revoked: false,
      );
      if (!sync.accepted) {
        final failure = PurchaseResult.failure(sync.message.isEmpty
            ? 'The purchase could not be recorded.'
            : sync.message);
        _setPurchase(failure);
        return failure;
      }
      _inventory = grantItems(_inventory, sync.grantedItemIds);
      await refreshEntitlement();
      _history = await backend.purchaseHistory(account.id);
      _message = sync.duplicate
          ? 'Already owned — no second charge was made.'
          : 'Purchase complete.';
    }

    _setPurchase(result);
    return result;
  }

  PurchaseResult? _lastPurchase;

  void _setPurchase(PurchaseResult result) {
    _lastPurchase = result;
    _purchaseState = result.state;
    _message = result.message.isNotEmpty ? result.message : _message;
    notifyListeners();
  }

  Future<PurchaseResult> restorePurchases() async {
    _setPurchase(const PurchaseResult(state: PurchaseState.pending));
    final result = await store.restore();
    if (result.state == PurchaseState.restored ||
        result.state == PurchaseState.success) {
      await refreshEntitlement();
      _inventory = await backend.fetchInventory(account.id);
      _history = await backend.purchaseHistory(account.id);
      _message = 'Purchases restored.';
    }
    _setPurchase(result);
    return result;
  }

  Future<void> openManageSubscription() async {
    final opened = await store.openManageSubscription();
    if (!opened) _message = 'Subscription management is not available here.';
    notifyListeners();
  }

  // --- inventory --------------------------------------------------------

  void equip(ShopItem item) {
    if (!vipAccessAt(_entitlement, _clock()) && item.vipOnly) return;
    final next = equipItem(_inventory, item.category, item.id);
    if (next == _inventory) return;
    _inventory = next;
    notifyListeners();
    unawaited(_syncEquipped(item.category, item.id));
  }

  /// Best-effort mirror of the local equip onto the server.
  Future<void> _syncEquipped(ShopCategory category, String itemId) async {
    try {
      await backend.syncEquipped(
        accountId: account.id,
        category: category,
        itemId: itemId,
      );
    } catch (_) {
      // Offline: the local equip still stands and will re-sync on next load.
    }
  }

  void unequip(ShopCategory category) {
    final next = unequipItem(_inventory, category);
    if (next == _inventory) return;
    _inventory = next;
    notifyListeners();
  }

  String? blockReasonFor(ShopItem item) => purchaseBlockReason(
        item: item,
        product: item.isBundle ? productFor(item.bundleProductIds.first) : null,
        entitlement: _entitlement,
        now: _clock(),
      );

  // --- rewards ----------------------------------------------------------

  Future<void> openAdPrompt() async {
    _adState = AdPromptState.loading;
    notifyListeners();
    final ready = await ads.loadRewarded();
    _adState = ready ? AdPromptState.watching : AdPromptState.failed;
    if (!ready) _message = 'No advertisement is available right now.';
    notifyListeners();
  }

  void closeAdPrompt() {
    _adState = AdPromptState.hidden;
    notifyListeners();
  }

  /// Shows an advert and asks the SERVER whether it pays. The client callback
  /// alone never grants coins.
  Future<AdRewardDecision> watchRewardedAd() async {
    final result = await ads.showRewarded();
    if (!result.completed) {
      _message = result.message;
      closeAdPrompt();
      return const AdRewardDecision(AdRewardOutcome.rejected);
    }
    final decision = await backend.grantAdReward(
      accountId: account.id,
      eventId: result.eventId,
      utcDay: utcDayOf(_clock()),
      signatureValid: result.signatureValid,
      policy: _policy,
    );
    if (decision.granted) {
      _ledger = applyWalletEntry(
        _ledger,
        WalletEntry(
          entryId: '${result.eventId}:ledger',
          eventKey: result.eventId,
          delta: decision.coins,
          reason: WalletReason.adReward,
          occurredAtDay: utcDayOf(_clock()),
        ),
      );
      _message = '+${decision.coins} coins credited.';
    } else {
      _message = switch (decision.outcome) {
        AdRewardOutcome.dailyCapReached =>
          'Daily limit reached — ${_policy.maxPerUtcDay} advert rewards per day.',
        AdRewardOutcome.duplicate => 'That reward was already credited.',
        AdRewardOutcome.signatureInvalid =>
          'Reward rejected: advertisement could not be verified.',
        _ => 'No reward granted.',
      };
    }
    closeAdPrompt();
    return decision;
  }

  Future<AdRewardDecision> claimDailyReward() async {
    final decision = await backend.claimDailyReward(
      accountId: account.id,
      utcDay: utcDayOf(_clock()),
    );
    if (decision.granted) {
      _ledger = applyWalletEntry(
        _ledger,
        WalletEntry(
          entryId: 'daily:${utcDayOf(_clock())}',
          eventKey: 'daily:${utcDayOf(_clock())}',
          delta: decision.coins,
          reason: WalletReason.dailyReward,
          occurredAtDay: utcDayOf(_clock()),
        ),
      );
      _message = 'Daily reward claimed.';
    } else {
      _message = decision.outcome == AdRewardOutcome.duplicate
          ? 'Daily reward already claimed today.'
          : 'Daily reward unavailable.';
    }
    notifyListeners();
    return decision;
  }

  // --- tournaments ------------------------------------------------------

  Future<String?> joinTournament(Tournament tournament) async {
    final block = tournamentEntryBlock(
      tournament: tournament,
      alreadyJoined: tournament.participantIds.contains(account.id),
      now: _clock(),
    );
    if (block != null) {
      _message = block;
      notifyListeners();
      return block;
    }
    final error = await backend.joinTournament(
      accountId: account.id,
      tournamentId: tournament.id,
    );
    if (error != null) {
      _message = error;
      notifyListeners();
      return error;
    }
    _tournaments = [
      for (final t in _tournaments)
        t.id == tournament.id
            ? Tournament(
                id: t.id,
                name: t.name,
                sponsor: t.sponsor,
                startsAt: t.startsAt,
                endsAt: t.endsAt,
                entryRule: t.entryRule,
                prizes: t.prizes,
                status: t.status,
                approvalState: t.approvalState,
                participantIds: [...t.participantIds, account.id],
                sponsoredLabel: t.sponsoredLabel,
                freeEntryOnly: t.freeEntryOnly,
              )
            : t
    ];
    _message = 'Entry confirmed. Good luck!';
    notifyListeners();
    return null;
  }

  Future<List<TournamentScore>> standings(String tournamentId) =>
      backend.standings(tournamentId);

  Future<void> loadAdmin() async {
    _revenue = await backend.adminSummary();
    notifyListeners();
  }

  void clearMessage() {
    _message = '';
    notifyListeners();
  }
}
