import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../design/bm_theme.dart';
import '../player/player_profile.dart';
import '../settings/bm_audio_settings.dart';
import 'bm_supabase.dart';

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
      BuildContext context, OAuthProvider provider, String name) async {
    if (!BmAuth.available) return notConnected(context, 'Sign in with $name');
    final outcome = await BmAuth.signInWith(provider);
    if (!context.mounted) return;
    say(
      context,
      outcome == BmAuthOutcome.redirected
          ? 'Continue signing in with $name…'
          : 'Sign in with $name failed. It must be enabled for this Buzz '
              'Masters project in the Supabase dashboard.',
    );
  }

  /// Magic-link sign-in; also the account recovery route (no passwords).
  static Future<void> email(BuildContext context) async {
    if (!BmAuth.available) return notConnected(context, 'Email sign-in');
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BmColors.panel,
        title: Text('SIGN IN WITH EMAIL', style: BmText.display(18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              style: BmText.title(15),
              decoration: const InputDecoration(hintText: 'you@example.com'),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
            const SizedBox(height: 8),
            Text(
              'We email you a one-time sign-in link — no password to forget. '
              'Use the same address to recover your account on a new device.',
              style: BmText.body(11.5, color: BmColors.muted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('CANCEL', style: BmText.label(11)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text('SEND LINK',
                style: BmText.label(11, color: BmColors.gold)),
          ),
        ],
      ),
    );
    final address = email?.trim() ?? '';
    if (address.isEmpty || !context.mounted) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(address)) {
      return say(context, 'That does not look like an email address.');
    }
    final outcome = await BmAuth.signInWithEmail(address);
    if (!context.mounted) return;
    say(
      context,
      outcome == BmAuthOutcome.emailSent
          ? 'Check $address for your sign-in link.'
          : 'Could not send the sign-in link. Please try again.',
    );
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
