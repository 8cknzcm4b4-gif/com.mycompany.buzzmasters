import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The dedicated Buzz Masters Supabase project, from build configuration:
///
///   flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=<publishable key>
///
/// Only the public (publishable/anon) key ever ships in the app. With nothing
/// defined, every online feature reports that it is not connected.
abstract final class BmSupabase {
  static const url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Where OAuth and magic links return to. The scheme and host are already
  /// registered in ios/Runner/Info.plist and AndroidManifest.xml. On web the
  /// site URL configured in the Supabase dashboard is used instead.
  static const redirectUrl = 'buzzmasters://buzzmasters.com/login-callback';

  static bool get credentialsPresent =>
      url.trim().startsWith('https://') && anonKey.trim().length > 20;

  static bool _ready = false;
  static Future<bool>? _initialising;

  /// True once [ensureInitialized] has connected the client.
  static bool get isReady => _ready;

  /// Initialises the client once; safe to call from several features.
  static Future<bool> ensureInitialized() => _initialising ??= _initialise();

  static Future<bool> _initialise() async {
    if (!credentialsPresent) return false;
    try {
      await Supabase.initialize(url: url, publishableKey: anonKey);
      _ready = true;
    } on Object catch (e) {
      debugPrint('Buzz Masters: Supabase init failed: $e');
      _ready = false;
    }
    return _ready;
  }

  static SupabaseClient get client => Supabase.instance.client;
}

/// What the account bar shows about the signed-in player.
@immutable
class BmAccount {
  const BmAccount({
    required this.userId,
    required this.isGuest,
    this.email,
    this.providers = const [],
  });

  final String userId;

  /// An anonymous Supabase session: online play works, progress is tied to
  /// this device until a provider is linked.
  final bool isGuest;
  final String? email;
  final List<String> providers;
}

enum BmAuthOutcome { signedIn, redirected, emailSent, unavailable, failed }

/// Supabase authentication for Buzz Masters.
///
/// Players start with an anonymous session so they can race online at once.
/// Signing in with Apple, Google or email from a guest session *links* that
/// identity to the same user, so races and friends carry over.
abstract final class BmAuth {
  static final ValueNotifier<BmAccount?> account = ValueNotifier(null);
  static StreamSubscription<AuthState>? _sub;
  static String? lastError;

  static bool get available => BmSupabase.isReady;

  static void _watch() {
    if (_sub != null || !available) return;
    _publish(BmSupabase.client.auth.currentUser);
    _sub = BmSupabase.client.auth.onAuthStateChange
        .listen((s) => _publish(s.session?.user));
  }

  static void _publish(User? user) {
    if (user == null) {
      account.value = null;
      return;
    }
    account.value = BmAccount(
      userId: user.id,
      isGuest: user.isAnonymous,
      email: user.email,
      providers: [
        for (final i in user.identities ?? const <UserIdentity>[]) i.provider,
      ],
    );
  }

  /// A session to call the game API with: the current one, or a new guest.
  /// Requires "Anonymous sign-ins" to be enabled in the Supabase dashboard.
  static Future<bool> ensureSession() async => await sessionProblem() == null;

  /// Null when a session is ready; otherwise 'offline' when the server could
  /// not be reached, or 'sign_in_failed' when it refused the sign-in.
  static Future<String?> sessionProblem() async {
    if (!available) return 'not_configured';
    _watch();
    final auth = BmSupabase.client.auth;
    if (auth.currentSession != null) return null;
    try {
      await auth.signInAnonymously();
      return null;
    } on AuthRetryableFetchException catch (e) {
      lastError = '$e';
      return 'offline';
    } on AuthException catch (e) {
      lastError = '$e';
      return 'sign_in_failed';
    } on Object catch (e) {
      lastError = '$e';
      return 'offline';
    }
  }

  static Future<BmAuthOutcome> signInWith(OAuthProvider provider) async {
    if (!available) return BmAuthOutcome.unavailable;
    _watch();
    final auth = BmSupabase.client.auth;
    const redirect = kIsWeb ? null : BmSupabase.redirectUrl;
    try {
      final guest = auth.currentUser?.isAnonymous ?? false;
      final launched = guest
          ? await auth.linkIdentity(provider, redirectTo: redirect)
          : await auth.signInWithOAuth(provider, redirectTo: redirect);
      return launched ? BmAuthOutcome.redirected : BmAuthOutcome.failed;
    } on Object catch (e) {
      lastError = '$e';
      return BmAuthOutcome.failed;
    }
  }

  /// Sends a magic link. From a guest session the email is attached to the
  /// same user once confirmed.
  static Future<BmAuthOutcome> signInWithEmail(String email) async {
    if (!available) return BmAuthOutcome.unavailable;
    _watch();
    final auth = BmSupabase.client.auth;
    try {
      if (auth.currentUser?.isAnonymous ?? false) {
        await auth.updateUser(UserAttributes(email: email),
            emailRedirectTo: kIsWeb ? null : BmSupabase.redirectUrl);
      } else {
        await auth.signInWithOtp(
            email: email,
            emailRedirectTo: kIsWeb ? null : BmSupabase.redirectUrl);
      }
      return BmAuthOutcome.emailSent;
    } on Object catch (e) {
      lastError = '$e';
      return BmAuthOutcome.failed;
    }
  }

  static Future<void> signOut() async {
    if (!available) return;
    try {
      await BmSupabase.client.auth.signOut();
    } on Object catch (e) {
      lastError = '$e';
    }
  }
}
