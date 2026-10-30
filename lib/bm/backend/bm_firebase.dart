import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// The Buzz Masters Firebase project (`buzz-masters-race`), configured by
/// `flutterfire configure` in lib/firebase_options.dart. Its keys are public
/// app identifiers; everything secret lives in Cloud Functions.
abstract final class BmFirebase {
  /// Cloud Functions run in London, next to the Firestore database.
  static const region = 'europe-west2';

  /// Builds can opt out with --dart-define=BM_OFFLINE=true (e.g. demos).
  static const _offline = bool.fromEnvironment('BM_OFFLINE');

  static bool _ready = false;
  static Future<bool>? _initialising;

  /// True once [ensureInitialized] has connected Firebase.
  static bool get isReady => _ready;

  static Future<bool> ensureInitialized() => _initialising ??= _initialise();

  static Future<bool> _initialise() async {
    if (_offline) return false;
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      if (!kIsWeb) {
        // Attests that calls come from the real app. Enforced server-side
        // once App Attest / Play Integrity are registered for the apps.
        await FirebaseAppCheck.instance.activate(
          providerApple: kDebugMode
              ? const AppleDebugProvider()
              : const AppleAppAttestWithDeviceCheckFallbackProvider(),
          providerAndroid: kDebugMode
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
        );
      }
      _ready = true;
    } on Object catch (e) {
      debugPrint('Buzz Masters: Firebase init failed: $e');
      _ready = false;
    }
    return _ready;
  }

  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: region);
}

/// What the account panel shows about the signed-in player.
@immutable
class BmAccount {
  const BmAccount({
    required this.userId,
    required this.isGuest,
    this.email,
    this.providers = const [],
  });

  final String userId;

  /// An anonymous session: online play works, progress is tied to this
  /// device until Apple, Google or email is linked.
  final bool isGuest;
  final String? email;
  final List<String> providers;
}

enum BmSignInProvider { apple, google }

enum BmAuthOutcome { signedIn, emailSent, unavailable, cancelled, failed }

/// Firebase Authentication for Buzz Masters.
///
/// Players start with an anonymous session so they can race online at once.
/// Signing in with Apple, Google or email from a guest session *links* that
/// identity to the same user, so races, friends and purchases carry over.
/// Sessions persist across launches (Firebase's default).
abstract final class BmAuth {
  static final ValueNotifier<BmAccount?> account = ValueNotifier(null);
  static StreamSubscription<User?>? _sub;
  static String? lastError;

  static bool get available => BmFirebase.isReady;

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static void _watch() {
    if (_sub != null || !available) return;
    _publish(_auth.currentUser);
    _sub = _auth.userChanges().listen(_publish);
  }

  static void _publish(User? user) {
    if (user == null) {
      account.value = null;
      return;
    }
    account.value = BmAccount(
      userId: user.uid,
      isGuest: user.isAnonymous,
      email: user.email,
      providers: [for (final p in user.providerData) p.providerId],
    );
  }

  /// The signed-in user's id, if any.
  static String? get uid => available ? _auth.currentUser?.uid : null;

  static Future<bool> ensureSession() async => await sessionProblem() == null;

  /// Null when a session is ready; otherwise 'not_configured', 'offline'
  /// when Firebase could not be reached, or 'sign_in_failed' when it refused.
  static Future<String?> sessionProblem() async {
    if (!available) return 'not_configured';
    _watch();
    if (_auth.currentUser != null) return null;
    try {
      await _auth.signInAnonymously();
      return null;
    } on FirebaseAuthException catch (e) {
      lastError = '${e.code}: ${e.message}';
      return e.code == 'network-request-failed' ? 'offline' : 'sign_in_failed';
    } on Object catch (e) {
      lastError = '$e';
      return 'offline';
    }
  }

  static AuthProvider _provider(BmSignInProvider p) => switch (p) {
        BmSignInProvider.apple => AppleAuthProvider()
          ..addScope('email')
          ..addScope('name'),
        BmSignInProvider.google => GoogleAuthProvider()..addScope('email'),
      };

  /// Sign in with Apple or Google. From a guest session the identity is
  /// linked to the same account; if it already belongs to another account,
  /// that account is signed in instead.
  static Future<BmAuthOutcome> signInWith(BmSignInProvider which) async {
    if (!available) return BmAuthOutcome.unavailable;
    _watch();
    final provider = _provider(which);
    final user = _auth.currentUser;
    try {
      if (user != null && user.isAnonymous) {
        try {
          kIsWeb
              ? await user.linkWithPopup(provider)
              : await user.linkWithProvider(provider);
        } on FirebaseAuthException catch (e) {
          final credential = e.credential;
          if (e.code != 'credential-already-in-use' || credential == null) {
            rethrow;
          }
          await _auth.signInWithCredential(credential);
        }
      } else {
        kIsWeb
            ? await _auth.signInWithPopup(provider)
            : await _auth.signInWithProvider(provider);
      }
      return BmAuthOutcome.signedIn;
    } on FirebaseAuthException catch (e) {
      lastError = '${e.code}: ${e.message}';
      return e.code == 'canceled' ||
              e.code == 'web-context-canceled' ||
              e.code == 'popup-closed-by-user'
          ? BmAuthOutcome.cancelled
          : BmAuthOutcome.failed;
    } on Object catch (e) {
      lastError = '$e';
      return BmAuthOutcome.failed;
    }
  }

  /// Creates an email + password account (linked to the guest session).
  static Future<String?> registerWithEmail(
      String email, String password) async {
    if (!available) return 'Accounts are not connected in this build.';
    _watch();
    try {
      final user = _auth.currentUser;
      final credential =
          EmailAuthProvider.credential(email: email, password: password);
      if (user != null && user.isAnonymous) {
        await user.linkWithCredential(credential);
      } else {
        await _auth.createUserWithEmailAndPassword(
            email: email, password: password);
      }
      return null;
    } on FirebaseAuthException catch (e) {
      lastError = '${e.code}: ${e.message}';
      return _emailMessage(e.code);
    }
  }

  static Future<String?> signInWithEmail(String email, String password) async {
    if (!available) return 'Accounts are not connected in this build.';
    _watch();
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      lastError = '${e.code}: ${e.message}';
      return _emailMessage(e.code);
    }
  }

  /// Account recovery: Firebase emails a password-reset link.
  static Future<String?> sendPasswordReset(String email) async {
    if (!available) return 'Accounts are not connected in this build.';
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      lastError = '${e.code}: ${e.message}';
      // Do not reveal whether an address has an account.
      return e.code == 'invalid-email' ? _emailMessage(e.code) : null;
    }
  }

  static String _emailMessage(String code) => switch (code) {
        'invalid-email' => 'That does not look like an email address.',
        'weak-password' => 'Choose a password of at least 8 characters.',
        'email-already-in-use' ||
        'credential-already-in-use' =>
          'That email already has an account. Sign in instead.',
        'wrong-password' ||
        'user-not-found' ||
        'invalid-credential' =>
          'Email or password is not right.',
        'too-many-requests' => 'Too many attempts. Please wait and try again.',
        'network-request-failed' =>
          'Could not reach the Buzz Masters server. Check your connection.',
        'operation-not-allowed' =>
          'Email sign-in is not enabled for Buzz Masters yet.',
        _ => 'Something went wrong ($code). Please try again.',
      };

  /// Deletes the player's account and server data (deleteAccount function),
  /// then signs out. Returns null on success, else a message.
  static Future<String?> deleteAccount() async {
    if (!available) return 'Accounts are not connected in this build.';
    if (_auth.currentUser == null) {
      return 'There is no account signed in on this device.';
    }
    try {
      final res =
          await BmFirebase.functions.httpsCallable('deleteAccount').call();
      final data = res.data;
      if (data is! Map || data['ok'] != true) {
        return 'The server could not delete the account. Please try again.';
      }
    } on Object catch (e) {
      lastError = '$e';
      return 'Could not reach the Buzz Masters server. Please try again.';
    }
    await signOut();
    return null;
  }

  static Future<void> signOut() async {
    if (!available) return;
    try {
      await _auth.signOut();
    } on Object catch (e) {
      lastError = '$e';
    }
  }
}

/// Push notifications for friend requests, race invites and results.
/// Asked for only when the player opens Friends, never at launch.
abstract final class BmPush {
  static bool _registered = false;
  static StreamSubscription<String>? _tokens;

  static Future<void> register() async {
    if (_registered || !BmAuth.available || BmAuth.uid == null) return;
    _registered = true;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // The token arrives on onRegistered, and again whenever it rotates.
      _tokens ??= messaging.onRegistered.listen((token) async {
        try {
          await BmFirebase.functions.httpsCallable('apiCall').call({
            'op': 'registerDevice',
            'args': {'token': token, 'platform': defaultTargetPlatform.name},
          });
        } on Object catch (e) {
          debugPrint('Buzz Masters: push token not saved: $e');
        }
      });
      await messaging.register();
    } on Object catch (e) {
      debugPrint('Buzz Masters: push registration skipped: $e');
    }
  }
}
