/// Supabase adapter for [MonetisationBackend].
///
/// Every mutation is a call to a Postgres function (RPC) so the rules —
/// idempotency, daily caps, entitlement checks — are enforced inside the
/// database transaction, not here. This file never writes a balance itself.
library;

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'gateways.dart';
import 'models.dart';

class SupabaseBackend implements MonetisationBackend {
  SupabaseBackend({required this.url, required this.anonKey});

  /// Public project URL and anon (publishable) key. The service-role key must
  /// never appear in the app.
  final String url;
  final String anonKey;

  bool _configured = false;

  @override
  bool get isConfigured => _configured;

  static bool credentialsPresent(
          {required String url, required String anonKey}) =>
      url.trim().startsWith('http') && anonKey.trim().length > 20;

  Future<void> configure() async {
    if (!credentialsPresent(url: url, anonKey: anonKey) || _configured) return;
    await Supabase.initialize(url: url, publishableKey: anonKey);
    _configured = true;
  }

  SupabaseClient get _client => Supabase.instance.client;

  Future<T> _rpc<T>(
    String fn,
    Map<String, dynamic> params,
    T Function(Object? raw) parse,
  ) async {
    final raw = await _client.rpc(fn, params: params);
    return parse(raw);
  }

  static int _asInt(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool _asBool(Object? value) => value == true;

  @override
  Future<VipEntitlement> fetchEntitlement(String accountId) async {
    if (!_configured) return const VipEntitlement.none();
    try {
      final raw = await _rpc<Object?>(
        'monetisation_entitlement',
        {'p_account_id': accountId},
        (r) => r,
      );
      final map = raw is Map ? raw : const <String, Object?>{};
      final active = _asBool(map['active']);
      if (!active) return const VipEntitlement.none();
      final expires = map['expires_at'];
      return VipEntitlement(
        isActive: true,
        source: map['source'] == 'store'
            ? EntitlementSource.storeVerified
            : EntitlementSource.validationFailed,
        productId: map['product_id'] as String?,
        expiresAt: expires == null ? null : DateTime.tryParse('$expires'),
        willRenew: _asBool(map['will_renew']),
        period: map['product_id'] == ProductIds.vipMonthly
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
      final rows = await _client
          .from('player_inventory')
          .select()
          .eq('account_id', accountId);
      final owned = <String>{};
      final equipped = <ShopCategory, String>{};
      var coins = 0;
      for (final row in rows as List<dynamic>) {
        final map = Map<String, dynamic>.from(row as Map);
        final itemId = (map['item_id'] as String?) ?? '';
        if (itemId.isNotEmpty && map['equipped'] == true) {
          final category = _categoryFromDb(map['category'] as String? ?? '');
          if (category != null) equipped[category] = itemId;
        }
        if (itemId.isNotEmpty) owned.add(itemId);
        if (map['balance'] != null) coins = _asInt(map['balance']);
      }
      return InventorySnapshot(
        ownedItemIds: owned,
        equipped: equipped,
        coins: coins,
        revision: 0,
      );
    } catch (error) {
      return const InventorySnapshot();
    }
  }

  static ShopCategory? _categoryFromDb(String value) {
    for (final category in ShopCategory.values) {
      if (category.name == value) return category;
    }
    return null;
  }

  @override
  Future<WalletLedger> fetchWallet(String accountId) async {
    if (!_configured) return const WalletLedger();
    try {
      final rows = await _client
          .from('wallet_transactions')
          .select()
          .eq('account_id', accountId)
          .order('created_at', ascending: false)
          .limit(200);
      var balance = 0;
      final entries = <WalletEntry>[];
      for (final row in rows as List<dynamic>) {
        final map = Map<String, dynamic>.from(row as Map);
        balance += _asInt(map['delta']);
        entries.add(WalletEntry(
          entryId: (map['id'] as String?) ?? '',
          eventKey: (map['dedupe_key'] as String?) ?? '',
          delta: _asInt(map['delta']),
          reason: _reasonFromDb(map['reason'] as String? ?? ''),
          occurredAtDay: _asInt(map['utc_day']),
        ));
      }
      return WalletLedger(entries: entries.reversed.toList(), balance: balance);
    } catch (error) {
      return const WalletLedger();
    }
  }

  static WalletReason _reasonFromDb(String value) => switch (value) {
        'ad_reward' => WalletReason.adReward,
        'daily_reward' => WalletReason.dailyReward,
        'purchase_grant' => WalletReason.purchaseGrant,
        _ => WalletReason.adminAdjustment,
      };

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
    try {
      final raw = await _rpc<Object?>(
        'monetisation_record_purchase',
        {
          'p_account_id': accountId,
          'p_transaction_id': transactionId,
          'p_product_id': productId,
          'p_price_string': priceString,
          'p_revoked': revoked,
        },
        (r) => r,
      );
      final map = raw is Map ? raw : const <String, Object?>{};
      final granted = <String>[
        if (map['granted_item_ids'] is List)
          for (final id in map['granted_item_ids'] as List) '$id',
      ];
      return PurchaseSyncResult(
        accepted: _asBool(map['accepted']),
        grantedItemIds: granted,
        duplicate: _asBool(map['duplicate']),
        message: (map['message'] as String?) ?? '',
      );
    } catch (error) {
      return PurchaseSyncResult(
        accepted: false,
        message: 'Purchase could not be recorded: $error',
      );
    }
  }

  @override
  Future<List<PurchaseRecord>> purchaseHistory(String accountId) async {
    if (!_configured) return const [];
    try {
      final rows = await _client
          .from('purchase_events')
          .select()
          .eq('account_id', accountId)
          .order('created_at', ascending: false)
          .limit(100);
      return [
        for (final row in rows as List<dynamic>)
          _recordFromRow(Map<String, dynamic>.from(row as Map)),
      ];
    } catch (error) {
      return const [];
    }
  }

  PurchaseRecord _recordFromRow(Map<String, dynamic> row) => PurchaseRecord(
        transactionId: (row['transaction_id'] as String?) ?? '',
        productId: (row['product_id'] as String?) ?? '',
        purchasedAt:
            DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
        priceString: (row['price_string'] as String?) ?? '',
        revoked: row['revoked'] == true,
        state: row['state'] == 'failed'
            ? PurchaseState.failed
            : row['state'] == 'cancelled'
                ? PurchaseState.cancelled
                : PurchaseState.success,
      );

  @override
  Future<AdRewardDecision> grantAdReward({
    required String accountId,
    required String eventId,
    required int utcDay,
    required bool signatureValid,
    required AdRewardPolicy policy,
  }) async {
    if (!_configured) return const AdRewardDecision(AdRewardOutcome.rejected);
    try {
      final raw = await _rpc<Object?>(
        'monetisation_grant_ad_reward',
        {
          'p_account_id': accountId,
          'p_event_id': eventId,
          'p_utc_day': utcDay,
          'p_signature_valid': signatureValid,
          'p_coins': policy.sanitized().coinsPerReward,
          'p_max_per_day': policy.sanitized().maxPerUtcDay,
        },
        (r) => r,
      );
      final map = raw is Map ? raw : const <String, Object?>{};
      return AdRewardDecision(
        _outcomeFromDb(map['outcome'] as String? ?? 'rejected'),
        coins: _asInt(map['coins']),
        usedToday: _asInt(map['used_today']),
      );
    } catch (error) {
      return const AdRewardDecision(AdRewardOutcome.rejected);
    }
  }

  @override
  Future<AdRewardDecision> claimDailyReward({
    required String accountId,
    required int utcDay,
  }) async {
    if (!_configured) return const AdRewardDecision(AdRewardOutcome.rejected);
    try {
      final raw = await _rpc<Object?>(
        'monetisation_claim_daily_reward',
        {'p_account_id': accountId, 'p_utc_day': utcDay},
        (r) => r,
      );
      final map = raw is Map ? raw : const <String, Object?>{};
      return AdRewardDecision(
        _outcomeFromDb(map['outcome'] as String? ?? 'rejected'),
        coins: _asInt(map['coins']),
      );
    } catch (error) {
      return const AdRewardDecision(AdRewardOutcome.rejected);
    }
  }

  static AdRewardOutcome _outcomeFromDb(String value) => switch (value) {
        'granted' => AdRewardOutcome.granted,
        'duplicate' => AdRewardOutcome.duplicate,
        'daily_cap_reached' => AdRewardOutcome.dailyCapReached,
        'signature_invalid' => AdRewardOutcome.signatureInvalid,
        _ => AdRewardOutcome.rejected,
      };

  @override
  Future<void> syncEquipped({
    required String accountId,
    required ShopCategory category,
    required String itemId,
  }) async {
    if (!_configured) return;
    await _client.rpc('monetisation_equip', params: {
      'p_account_id': accountId,
      'p_category': category.name,
      'p_item_id': itemId,
    });
  }

  @override
  Future<List<Tournament>> tournaments() async {
    if (!_configured) return const [];
    try {
      final rows = await _client
          .from('sponsored_tournaments')
          .select()
          .order('starts_at', ascending: false);
      return [
        for (final row in rows as List<dynamic>)
          _tournamentFromRow(Map<String, dynamic>.from(row as Map)),
      ];
    } catch (error) {
      return const [];
    }
  }

  Tournament _tournamentFromRow(Map<String, dynamic> row) {
    final participants = <String>[
      if (row['participant_ids'] is List)
        for (final id in row['participant_ids'] as List) '$id',
    ];
    return Tournament(
      id: '${row['id']}',
      name: (row['name'] as String?) ?? 'Tournament',
      sponsor: Sponsor(
        businessName: (row['sponsor_name'] as String?) ?? '',
        logoAsset: (row['sponsor_logo'] as String?) ?? '',
        bannerAsset: (row['sponsor_banner'] as String?) ?? '',
        website: (row['sponsor_website'] as String?) ?? '',
      ),
      startsAt: DateTime.tryParse('${row['starts_at']}') ?? DateTime.now(),
      endsAt: DateTime.tryParse('${row['ends_at']}') ?? DateTime.now(),
      entryRule: (row['entry_rules'] as String?) ?? 'Free entry',
      prizes: [
        if (row['prizes'] is List)
          for (final p in row['prizes'] as List) '$p',
      ],
      status: _statusFromDb(row['status'] as String? ?? 'published'),
      approvalState: (row['approval_state'] as String?) ?? 'pending',
      participantIds: participants,
      sponsoredLabel: 'Sponsored',
      freeEntryOnly: row['free_entry_only'] != false,
    );
  }

  static TournamentStatus _statusFromDb(String value) => switch (value) {
        'draft' => TournamentStatus.draft,
        'live' => TournamentStatus.live,
        'closed' => TournamentStatus.closed,
        'archived' => TournamentStatus.archived,
        _ => TournamentStatus.published,
      };

  @override
  Future<String?> joinTournament({
    required String accountId,
    required String tournamentId,
  }) async {
    if (!_configured) return 'Backend is not configured.';
    try {
      final raw = await _rpc<Object?>(
        'monetisation_join_tournament',
        {
          'p_account_id': accountId,
          'p_tournament_id': tournamentId,
        },
        (r) => r,
      );
      final map = raw is Map ? raw : const <String, Object?>{};
      if (_asBool(map['joined'])) return null;
      return (map['message'] as String?) ?? 'Entry was refused.';
    } catch (error) {
      return 'Entry failed: $error';
    }
  }

  @override
  Future<List<TournamentScore>> standings(String tournamentId) async {
    if (!_configured) return const [];
    try {
      final rows = await _client
          .from('tournament_entries')
          .select()
          .eq('tournament_id', tournamentId);
      return [
        for (final row in rows as List<dynamic>)
          TournamentScore(
            playerId: '${(row as Map)['account_id']}',
            correct: _asInt(row['correct']),
            tiedBreakMs: _asInt(row['tie_break_ms']),
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
      final raw = await _rpc<Object?>(
        'monetisation_admin_summary',
        const {},
        (r) => r,
      );
      if (raw is! Map) return const AdminRevenueSummary.notConnected();
      final map = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
      return AdminRevenueSummary(
        vipMrr: _money(map['vip_mrr_pence']),
        cosmeticGross: _money(map['cosmetic_gross_pence']),
        adEarnings: _money(map['ad_earnings_pence']),
        sponsorRevenue: _money(map['sponsor_revenue_pence']),
        gross: _money(map['gross_pence']),
        fees: _money(map['fees_pence']),
        refunds: _money(map['refunds_pence']),
        taxEstimate: _money(map['tax_estimate_pence']),
        net: _money(map['net_pence']),
        activeVipCount: _asInt(map['active_vip']),
        cancellations30d: _asInt(map['cancellations_30d']),
        verifiedAdRewards: _asInt(map['verified_ad_rewards']),
        outstandingErrors: _asInt(map['outstanding_errors']),
      );
    } catch (error) {
      return const AdminRevenueSummary.notConnected();
    }
  }

  static MoneyStream _money(Object? value) => value == null
      ? const MoneyStream.notConnected()
      : MoneyStream(amountPence: _asInt(value));
}
