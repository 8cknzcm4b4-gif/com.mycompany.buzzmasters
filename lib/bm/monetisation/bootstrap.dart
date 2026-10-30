/// Wires the monetisation gateways from build configuration.
///
/// Everything is compile-time configuration (`--dart-define`), so no secret
/// ever lands in the repository. With nothing defined the app runs on the
/// honest "not connected" implementations: no fake prices, no fake purchases,
/// no invented revenue.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/bm_theme.dart';
import '../backend/bm_supabase.dart';
import 'admob_ads.dart';
import 'controller.dart';
import 'gateways.dart';
import 'revenuecat_store.dart';
import 'rules.dart';
import 'supabase_backend.dart';

/// Public, non-secret build configuration.
abstract final class MonetisationConfig {
  /// RevenueCat **public** SDK key. The secret key never ships in an app.
  static const revenueCatApiKey = String.fromEnvironment(
    'REVENUECAT_PUBLIC_API_KEY',
    defaultValue: '',
  );

  /// AdMob application id. Google's test id is used while developing.
  static const admobAppId = String.fromEnvironment(
    'ADMOB_APP_ID',
    defaultValue: 'ca-app-pub-3940256099942544~3347511713',
  );

  /// Rewarded unit id — Google's test unit until production is configured.
  static const admobRewardedUnitId = String.fromEnvironment(
    'ADMOB_REWARDED_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-3940256099942544/5224354917',
  );

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get storeConfigured => revenueCatApiKey.isNotEmpty;
  static bool get adsConfigured => admobRewardedUnitId.isNotEmpty;
  static bool get backendConfigured => SupabaseBackend.credentialsPresent(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
}

/// Stable id for the player's game account.
///
/// There is no sign-in yet, so this is generated once and kept on device. It
/// is the single value handed to RevenueCat, which is what makes restores and
/// cross-device entitlement work once real authentication lands.
abstract final class GameAccountStore {
  static const _key = 'bm_game_account_id';

  static Future<BmGameAccount> resolve() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.length >= 12) {
      return BmGameAccount(existing);
    }
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final created =
        'acct_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    await prefs.setString(_key, created);
    return BmGameAccount(created);
  }
}

abstract final class BmMonetisation {
  static MonetisationController? _controller;

  /// Builds (once) and loads the controller from the configured gateways.
  static Future<MonetisationController> ensure() async {
    final existing = _controller;
    if (existing != null) return existing;

    // With a server, the account is the signed-in Supabase user, which is
    // what the monetisation RLS policies (auth.uid() = account_id) expect.
    final account =
        await BmSupabase.ensureInitialized() && await BmAuth.ensureSession()
            ? BmGameAccount(BmSupabase.client.auth.currentUser!.id)
            : await GameAccountStore.resolve();

    final store = MonetisationConfig.storeConfigured
        ? RevenueCatStore(
            apiKey: MonetisationConfig.revenueCatApiKey,
            appUserId: account.id,
          )
        : const UnconfiguredStore();
    if (store is RevenueCatStore) await store.configure();

    final ads = AdMobRewardedAds(
      rewardedAdUnitId: MonetisationConfig.admobRewardedUnitId,
    );
    if (MonetisationConfig.adsConfigured) await ads.initialise();

    final backend = MonetisationConfig.backendConfigured
        ? SupabaseBackend(
            url: MonetisationConfig.supabaseUrl,
            anonKey: MonetisationConfig.supabaseAnonKey,
          )
        : const UnconfiguredBackend();
    if (backend is SupabaseBackend) await backend.configure();

    final controller = MonetisationController(
      store: store,
      backend: backend,
      ads: ads,
      account: account,
    );
    _controller = controller;
    await controller.load();
    return controller;
  }

  /// The controller once [ensure] has resolved. Screens built inside a
  /// [MonetisationScope] can reach it without threading it through every
  /// constructor.
  static MonetisationController get instance {
    final controller = _controller;
    if (controller == null) {
      throw StateError('Monetisation has not been initialised yet.');
    }
    return controller;
  }

  /// Test hook: inject a controller built from doubles.
  static void debugOverride(MonetisationController controller) {
    _controller = controller;
  }

  static void debugReset() => _controller = null;
}

/// Resolves the controller once and rebuilds [builder] whenever it changes.
class MonetisationScope extends StatefulWidget {
  const MonetisationScope({super.key, required this.builder});

  final Widget Function(BuildContext context, MonetisationController controller)
      builder;

  @override
  State<MonetisationScope> createState() => _MonetisationScopeState();
}

class _MonetisationScopeState extends State<MonetisationScope> {
  late final Future<MonetisationController> _future = BmMonetisation.ensure();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MonetisationController>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _BmFatal(
            message: 'Could not start the store: ${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: BmColors.cyan),
          );
        }
        final controller = snapshot.data!;
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) => widget.builder(context, controller),
        );
      },
    );
  }
}

class _BmFatal extends StatelessWidget {
  const _BmFatal({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: BmText.body(13, color: BmColors.muted),
        ),
      ),
    );
  }
}

/// Plain status banner used by every monetisation screen.
class BmStatusBanner extends StatelessWidget {
  const BmStatusBanner({super.key, required this.controller});

  final MonetisationController controller;

  @override
  Widget build(BuildContext context) {
    final message = controller.message;
    if (message.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: BmColors.panel.withValues(alpha: 0.9),
        border: Border.all(color: BmColors.cyan.withValues(alpha: 0.6)),
      ),
      child: Text(
        message,
        style: BmText.body(12, color: Colors.white),
      ),
    );
  }
}
