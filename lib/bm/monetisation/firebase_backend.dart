/// Firebase adapter for [MonetisationBackend].
///
/// Reads come straight from Firestore, where the security rules let a player
/// see only their own entitlement, wallet, items and purchases. Every change
/// goes through Cloud Functions, which verify with RevenueCat or Google and
/// apply each grant exactly once (functions/src/api.ts). Nothing here writes
/// a balance, an item or VIP status.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../backend/bm_firebase.dart';

import 'gateways.dart';
import 'models.dart';

class FirebaseBackend implements MonetisationBackend {
  FirebaseBackend();

  bool _configured = false;

  @override
  bool get isConfigured => _configured;

  Future<void> configure() async {
    if (_configured) return;
    _configured = await BmFirebase.ensureInitialized();
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<Map<String, dynamic>> _call(String name,
      [Map<String, dynamic> data = const {}]) async {
    final res = await BmFirebase.functions.httpsCallable(name).call<Object?>(data);
    final raw = res.data;
    return raw is Map ? raw.map((k, v) => MapEntry('$k', v)) : const {};
  }

  Future<Map<String, dynamic>> _api(String op, Map<String, dynamic> args) =>
      _call('apiCall', {'op': op, 'args': args});

  static int _asInt(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static DateTime? _date(Object? ms) =>
      ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;

  @override
  Future<VipEntitlement> fetchEntitlement(String accountId) async {
    if (!_configured) return const VipEntitlement.none();
    try {
      final snap = await _db.doc('entitlements/$accountId').get();
      final vip = (snap.data()?['vip'] as Map?) ?? const {};
      final expires = _date(vip['expiresAt']);
      final active = vip['active'] == true &&
          (expires == null || expires.isAfter(DateTime.now()));
      if (!active) return const VipEntitlement.none();
      return VipEntitlement(
        isActive: true,
        source: vip['source'] == 'store'
            ? EntitlementSource.storeVerified
            : EntitlementSource.validationFailed,
        productId: vip['productId'] as String?,
        expiresAt: expires,
        willRenew: vip['willRenew'] == true,
        period: vip['productId'] == ProductIds.vipMonthly
            ? VipPeriod.monthly
            : VipPeriod.annual,
        validatedAt: DateTime.now(),
      );
    } catch (error) {
      return const VipEntitlement(
        isActive: false,
        source: EntitlementSource.validationFailed,
      );
    }
  }

  @override
  Future<InventorySnapshot> fetchInventory(String accountId) async {
    if (!_configured) return const InventorySnapshot();
    try {
      final items = await _db.collection('inventory/$accountId/items').get();
      final wallet = await _db.doc('wallets/$accountId').get();
      final owned = <String>{};
      final equipped = <ShopCategory, String>{};
      for (final d in items.docs) {
        owned.add(d.id);
        if (d.data()['equipped'] == true) {
          final category = _category('${d.data()['category']}');
          if (category != null) equipped[category] = d.id;
        }
      }
      return InventorySnapshot(
        ownedItemIds: owned,
        equipped: equipped,
        coins: _asInt(wallet.data()?['balance']),
        revision: 0,
      );
    } catch (error) {
      return const InventorySnapshot();
    }
  }

  static ShopCategory? _category(String value) {
    for (final category in ShopCategory.values) {
      if (category.name == value) return category;
    }
    return null;
  }

  @override
  Future<WalletLedger> fetchWallet(String accountId) async {
    if (!_configured) return const WalletLedger();
    try {
      final rows = await _db
          .collection('wallets/$accountId/ledger')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
      var balance = 0;
      final entries = <WalletEntry>[];
      for (final d in rows.docs) {
        final m = d.data();
        balance += _asInt(m['delta']);
        entries.add(WalletEntry(
          entryId: d.id,
          eventKey: Uri.decodeComponent(d.id),
          delta: _asInt(m['delta']),
          reason: switch ('${m['reason']}') {
            'ad_reward' => WalletReason.adReward,
            'daily_reward' => WalletReason.dailyReward,
            'purchase_grant' => WalletReason.purchaseGrant,
            _ => WalletReason.adminAdjustment,
          },
          occurredAtDay: _asInt(m['utcDay']),
        ));
      }
      return WalletLedger(entries: entries.reversed.toList(), balance: balance);
    } catch (error) {
      return const WalletLedger();
    }
  }

  @override
  Future<PurchaseSyncResult> recordPurchase({
    required String accountId,
    required String transactionId,
    required String productId,
    required String priceString,
    required bool revoked,
  }) async {
    if (!_configured) {
      return const PurchaseSyncResult(
        accepted: false,
        message: 'Backend is not configured — ownership cannot be recorded.',
      );
    }
    // The app never records its own purchases: the server asks RevenueCat
    // (with the secret key) what this signed-in player owns and records that.
    // `transactionId`, `priceString` and `revoked` are ignored on purpose.
    try {
      final map = await _call('syncPurchases', {'product_id': productId});
      return PurchaseSyncResult(
        accepted: map['accepted'] == true,
        grantedItemIds: [
          if (map['granted_item_ids'] is List)
            for (final id in map['granted_item_ids'] as List) '$id',
        ],
        duplicate: map['duplicate'] == true,
        message: (map['message'] as String?) ?? '',
      );
    } catch (error) {
      return PurchaseSyncResult(
        accepted: false,
        message: 'The purchase could not be verified yet: $error',
      );
    }
  }

  @override
  Future<List<PurchaseRecord>> purchaseHistory(String accountId) async {
    if (!_configured) return const [];
    try {
      final rows = await _db
          .collection('purchases/$accountId/events')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();
      return [
        for (final d in rows.docs)
          PurchaseRecord(
            transactionId: '${d.data()['transactionId'] ?? ''}',
            productId: '${d.data()['productId'] ?? ''}',
            purchasedAt: _date(d.data()['createdAt']) ?? DateTime.now(),
            priceString: '${d.data()['price'] ?? ''}',
            revoked: d.data()['revoked'] == true,
            state: PurchaseState.success,
          ),
      ];
    } catch (error) {
      return const [];
    }
  }

  /// How long to wait for Google's verification callback to land.
  static const ssvPollAttempts = 10;
  static const ssvPollInterval = Duration(milliseconds: 1500);

  @override
  Future<AdRewardDecision> grantAdReward({
    required String accountId,
    required String eventId,
    required int utcDay,
    required bool signatureValid,
    required AdRewardPolicy policy,
  }) async {
    if (!_configured) return const AdRewardDecision(AdRewardOutcome.rejected);
    // Coins are credited only by Google's signed SSV callback (admobSsv
    // function). The app waits for that record; `signatureValid` from the
    // device is never trusted.
    final ref = _db
        .doc('adRewards/$accountId/events/${Uri.encodeComponent(eventId)}');
    for (var attempt = 0; attempt < ssvPollAttempts; attempt++) {
      try {
        final snap = await ref.get();
        if (snap.data()?['verification'] == 'ssv_verified') {
          return AdRewardDecision(AdRewardOutcome.granted,
              coins: _asInt(snap.data()?['coins']));
        }
      } catch (_) {
        // Keep waiting; a transient read failure is not a verdict.
      }
      await Future<void>.delayed(ssvPollInterval);
    }
    return const AdRewardDecision(AdRewardOutcome.signatureInvalid);
  }

  @override
  Future<AdRewardDecision> claimDailyReward({
    required String accountId,
    required int utcDay,
  }) async {
    if (!_configured) return const AdRewardDecision(AdRewardOutcome.rejected);
    try {
      final map = await _api('claimDailyReward', {'utcDay': utcDay});
      return AdRewardDecision(
        switch ('${map['outcome']}') {
          'granted' => AdRewardOutcome.granted,
          'duplicate' => AdRewardOutcome.duplicate,
          'daily_cap_reached' => AdRewardOutcome.dailyCapReached,
          _ => AdRewardOutcome.rejected,
        },
        coins: _asInt(map['coins']),
      );
    } catch (error) {
      return const AdRewardDecision(AdRewardOutcome.rejected);
    }
  }

  @override
  Future<void> syncEquipped({
    required String accountId,
    required ShopCategory category,
    required String itemId,
  }) async {
    if (!_configured) return;
    final map = await _api('equip', {'category': category.name, 'itemId': itemId});
    if (map['ok'] != true) throw StateError('${map['error']}');
  }

  @override
  Future<List<Tournament>> tournaments() async {
    if (!_configured) return const [];
    try {
      final rows = await _db
          .collection('tournaments')
          .where('status', whereIn: ['published', 'live', 'closed'])
          .get();
      final uid = BmAuth.uid;
      final list = <Tournament>[];
      for (final d in rows.docs) {
        final m = d.data();
        final mine = uid == null
            ? null
            : await _db.doc('tournaments/${d.id}/entries/$uid').get();
        list.add(Tournament(
          id: d.id,
          name: (m['name'] as String?) ?? 'Tournament',
          sponsor: Sponsor(
            businessName: (m['sponsorName'] as String?) ?? '',
            logoAsset: (m['sponsorLogo'] as String?) ?? '',
            bannerAsset: (m['sponsorBanner'] as String?) ?? '',
            website: (m['sponsorWebsite'] as String?) ?? '',
          ),
          startsAt: _date(m['startsAt']) ?? DateTime.now(),
          endsAt: _date(m['endsAt']) ?? DateTime.now(),
          entryRule: (m['entryRules'] as String?) ?? 'Free entry',
          prizes: [
            if (m['prizes'] is List)
              for (final p in m['prizes'] as List) '$p',
          ],
          status: switch ('${m['status']}') {
            'live' => TournamentStatus.live,
            'closed' => TournamentStatus.closed,
            _ => TournamentStatus.published,
          },
          approvalState: (m['approvalState'] as String?) ?? 'approved',
          participantIds: [if (mine?.exists ?? false) uid!],
          sponsoredLabel: 'Sponsored',
          freeEntryOnly: m['freeEntryOnly'] != false,
        ));
      }
      list.sort((a, b) => b.startsAt.compareTo(a.startsAt));
      return list;
    } catch (error) {
      return const [];
    }
  }

  @override
  Future<String?> joinTournament({
    required String accountId,
    required String tournamentId,
  }) async {
    if (!_configured) return 'Backend is not configured.';
    try {
      final map = await _api('joinTournament', {'tournamentId': tournamentId});
      if (map['joined'] == true) return null;
      return (map['message'] as String?) ?? 'Entry was refused.';
    } catch (error) {
      return 'Entry failed: $error';
    }
  }

  @override
  Future<List<TournamentScore>> standings(String tournamentId) async {
    if (!_configured) return const [];
    try {
      final map = await _api('standings', {'tournamentId': tournamentId});
      return [
        for (final s in (map['scores'] as List?) ?? const [])
          TournamentScore(
            playerId: '${(s as Map)['player_id']}',
            correct: _asInt(s['correct']),
            tiedBreakMs: _asInt(s['tie_break_ms']),
          ),
      ];
    } catch (error) {
      return const [];
    }
  }

  @override
  Future<AdminRevenueSummary> adminSummary() async {
    if (!_configured) return const AdminRevenueSummary.notConnected();
    try {
      final map = await _call('adminSummary');
      // Revenue amounts come from the stores' own reports, not this app.
      return AdminRevenueSummary(
        vipMrr: const MoneyStream.notConnected(),
        cosmeticGross: const MoneyStream.notConnected(),
        adEarnings: const MoneyStream.notConnected(),
        sponsorRevenue: const MoneyStream.notConnected(),
        gross: const MoneyStream.notConnected(),
        fees: const MoneyStream.notConnected(),
        refunds: const MoneyStream.notConnected(),
        taxEstimate: const MoneyStream.notConnected(),
        net: const MoneyStream.notConnected(),
        activeVipCount: _asInt(map['active_vip']),
        cancellations30d: 0,
        verifiedAdRewards: _asInt(map['verified_ad_rewards']),
        outstandingErrors: 0,
      );
    } catch (error) {
      return const AdminRevenueSummary.notConnected();
    }
  }
}
