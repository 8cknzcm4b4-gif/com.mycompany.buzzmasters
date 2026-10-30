import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/bm_theme.dart';
import '../player/player_profile.dart';
import '../settings/bm_audio_settings.dart';
import 'bm_firebase.dart';

/// Account actions shared by the welcome screen and settings.
abstract final class AccountActions {
  static void say(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: BmColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: BmColors.cyan.withValues(alpha: 0.5)),
        ),
        content: Text(text, style: BmText.body(12.5)),
      ));

  static void notConnected(BuildContext context, String what) => say(
        context,
        '$what is not available yet: Buzz Masters accounts need the game '
        'server, which this build is not connected to. You can keep playing '
        'as a guest.',
      );

  static Future<void> oauth(
      BuildContext context, BmSignInProvider provider, String name) async {
    if (!BmAuth.available) return notConnected(context, 'Sign in with $name');
    final outcome = await BmAuth.signInWith(provider);
    if (!context.mounted) return;
    switch (outcome) {
      case BmAuthOutcome.signedIn:
        say(context, 'Signed in with $name.');
      case BmAuthOutcome.cancelled:
        break;
      default:
        say(
            context,
            'Sign in with $name failed. It must be enabled for Buzz Masters '
            'in the Firebase console (Authentication → Sign-in method).');
    }
  }

  /// Email + password: sign in, create an account (kept with the guest
  /// progress), or recover a forgotten password by email.
  static Future<void> email(BuildContext context) async {
    if (!BmAuth.available) return notConnected(context, 'Email sign-in');
    final result = await showDialog<_EmailRequest>(
      context: context,
      builder: (_) => const _EmailDialog(),
    );
    if (result == null || !context.mounted) return;
    final address = result.email.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(address)) {
      return say(context, 'That does not look like an email address.');
    }
    String? problem;
    switch (result.mode) {
      case _EmailMode.reset:
        problem = await BmAuth.sendPasswordReset(address);
        if (!context.mounted) return;
        return say(
            context,
            problem ??
                'If $address has an account, a password reset link is on '
                    'its way.');
      case _EmailMode.register:
        if (result.password.length < 8) {
          return say(context, 'Choose a password of at least 8 characters.');
        }
        problem = await BmAuth.registerWithEmail(address, result.password);
      case _EmailMode.signIn:
        problem = await BmAuth.signInWithEmail(address, result.password);
    }
    if (!context.mounted) return;
    say(context, problem ?? 'Signed in as $address.');
  }

  /// Erases everything this app stored on the device.
  static Future<void> eraseDeviceData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } on Object {
      // Nothing stored.
    }
    PlayerProfileStore.reset();
    BmAudioSettings.reset();
  }

  /// Asks for explicit confirmation, deletes the online account if there is
  /// one, then erases the device data. Returns true when everything is gone.
  static Future<bool> confirmAndDelete(BuildContext context) async {
    final online = BmAuth.available && BmAuth.account.value != null;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: BmColors.panel,
          title: Text(online ? 'DELETE ACCOUNT?' : 'ERASE DEVICE DATA?',
              style: BmText.display(18, color: BmColors.red)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                online
                    ? 'This permanently deletes your Buzz Masters account: '
                        'profile, race history, friends, coins, items and VIP '
                        'records. It cannot be undone.\n\nAn active VIP '
                        'subscription is billed by Apple or Google: cancel it '
                        'in your store subscription settings to stop renewals.'
                    : 'This erases your racing name, stats, achievements, '
                        'best times and settings from this device. It cannot '
                        'be undone.',
                style: BmText.body(12.5, color: const Color(0xFFD5DAF5)),
              ),
              const SizedBox(height: 12),
              Text('Type DELETE to confirm', style: BmText.label(9)),
              TextField(
                key: const ValueKey('delete-confirm-field'),
                controller: controller,
                onChanged: (_) => setState(() {}),
                style: BmText.title(15),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('CANCEL', style: BmText.label(11)),
            ),
            TextButton(
              onPressed: controller.text.trim().toUpperCase() == 'DELETE'
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: Text('DELETE',
                  style: BmText.label(11,
                      color: controller.text.trim().toUpperCase() == 'DELETE'
                          ? BmColors.red
                          : BmColors.muted)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return false;
    if (online) {
      final problem = await BmAuth.deleteAccount();
      if (!context.mounted) return false;
      if (problem != null) {
        say(context, problem);
        return false;
      }
    }
    await eraseDeviceData();
    if (!context.mounted) return true;
    say(context,
        online ? 'Your account has been deleted.' : 'Device data erased.');
    return true;
  }
}

enum _EmailMode { signIn, register, reset }

class _EmailRequest {
  const _EmailRequest(this.mode, this.email, this.password);
  final _EmailMode mode;
  final String email;
  final String password;
}

class _EmailDialog extends StatefulWidget {
  const _EmailDialog();

  @override
  State<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<_EmailDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  _EmailMode _mode = _EmailMode.signIn;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context)
      .pop(_EmailRequest(_mode, _email.text, _password.text));

  @override
  Widget build(BuildContext context) {
    final title = switch (_mode) {
      _EmailMode.signIn => 'SIGN IN WITH EMAIL',
      _EmailMode.register => 'CREATE AN ACCOUNT',
      _EmailMode.reset => 'RESET PASSWORD',
    };
    final action = switch (_mode) {
      _EmailMode.signIn => 'SIGN IN',
      _EmailMode.register => 'CREATE',
      _EmailMode.reset => 'SEND LINK',
    };
    Widget link(String text, _EmailMode mode, String key) => TextButton(
          key: ValueKey(key),
          onPressed: () => setState(() => _mode = mode),
          child: Text(text, style: BmText.label(9.5, color: BmColors.cyan)),
        );
    return AlertDialog(
      backgroundColor: BmColors.panel,
      title: Text(title, style: BmText.display(18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('email-field'),
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              style: BmText.title(15),
              decoration: const InputDecoration(hintText: 'you@example.com'),
            ),
            if (_mode != _EmailMode.reset)
              TextField(
                key: const ValueKey('password-field'),
                controller: _password,
                obscureText: true,
                autofillHints: [
                  _mode == _EmailMode.register
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                style: BmText.title(15),
                decoration: InputDecoration(
                    hintText: _mode == _EmailMode.register
                        ? 'Password (8+ characters)'
                        : 'Password'),
                onSubmitted: (_) => _submit(),
              ),
            const SizedBox(height: 8),
            Text(
              switch (_mode) {
                _EmailMode.signIn =>
                  'Use the same email on any device to keep your progress.',
                _EmailMode.register =>
                  'Your guest races, friends and purchases move to this '
                      'account.',
                _EmailMode.reset =>
                  'We email you a link to choose a new password.',
              },
              style: BmText.body(11.5, color: BmColors.muted),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                if (_mode != _EmailMode.signIn)
                  link('I HAVE AN ACCOUNT', _EmailMode.signIn, 'email-mode-signin'),
                if (_mode != _EmailMode.register)
                  link('CREATE ACCOUNT', _EmailMode.register, 'email-mode-register'),
                if (_mode != _EmailMode.reset)
                  link('FORGOT PASSWORD?', _EmailMode.reset, 'email-mode-reset'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CANCEL', style: BmText.label(11)),
        ),
        TextButton(
          key: const ValueKey('email-submit'),
          onPressed: _submit,
          child: Text(action, style: BmText.label(11, color: BmColors.gold)),
        ),
      ],
    );
  }
}
