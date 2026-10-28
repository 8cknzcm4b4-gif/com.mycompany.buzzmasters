import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../widgets/bm_button.dart';
import '../widgets/studio_background.dart';
import 'main_menu_screen.dart';
import 'matchmaking_screen.dart';

/// Screen 2 — Welcome: logo over the animated studio with every sign-in path.
class BmWelcomeScreen extends StatelessWidget {
  const BmWelcomeScreen({super.key});

  void _openMenu(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BmMainMenuScreen()),
    );
  }

  void _openMatchmaking(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BmMatchmakingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      const SizedBox(height: 12),
                      Image.asset('assets/images/bm_logo.png', width: 300),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/images/bm_hero.png',
                          width: 300,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                  ),
                  Column(
                    children: [
                      BmButton(
                        label: 'PLAY NOW',
                        icon: Icons.play_arrow_rounded,
                        height: 58,
                        fontSize: 17,
                        onPressed: () => _openMatchmaking(context),
                      ),
                      const SizedBox(height: 12),
                      BmButton(
                        label: 'PLAY WITH FRIENDS',
                        icon: Icons.people_alt_rounded,
                        style: BmButtonStyle.cyan,
                        onPressed: () => _openMatchmaking(context),
                      ),
                      const SizedBox(height: 18),
                      BmButton(
                        label: 'PLAY AS GUEST',
                        style: BmButtonStyle.outline,
                        onPressed: () => _openMenu(context),
                      ),
                      const SizedBox(height: 22),
                      _divider(),
                      const SizedBox(height: 16),
                      BmButton(
                        label: 'Sign in with Apple',
                        icon: Icons.apple,
                        style: BmButtonStyle.white,
                        height: 50,
                        fontSize: 14,
                        onPressed: () => _signIn(context, 'Apple'),
                      ),
                      const SizedBox(height: 10),
                      BmButton(
                        label: 'Sign in with Google',
                        icon: Icons.g_mobiledata_rounded,
                        style: BmButtonStyle.white,
                        height: 50,
                        fontSize: 14,
                        onPressed: () => _signIn(context, 'Google'),
                      ),
                      const SizedBox(height: 10),
                      BmButton(
                        label: 'Sign in with Email',
                        icon: Icons.mail_rounded,
                        style: BmButtonStyle.violet,
                        height: 50,
                        fontSize: 14,
                        onPressed: () => _emailNotice(context),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => _emailNotice(context),
                        child: Text(
                          'Create Account',
                          style: BmText.body(13, color: BmColors.cyan)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _footerLink('Terms'),
                          _dot(),
                          _footerLink('Privacy Policy'),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _divider() => Row(
        children: [
          Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.18))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('OR', style: BmText.label(10, spacing: 2)),
          ),
          Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.18))),
        ],
      );

  Widget _footerLink(String text) => Text(
        text,
        style: BmText.body(11, color: BmColors.muted)
            .copyWith(decoration: TextDecoration.underline),
      );

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('·', style: BmText.body(11, color: BmColors.muted)),
      );

  void _signIn(BuildContext context, String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: BmColors.panel,
        content: Text(
          '$provider sign-in is not configured yet: no OAuth client or '
          'Buzz Masters backend is connected.',
          style: BmText.body(12),
        ),
      ),
    );
  }

  void _emailNotice(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: BmColors.panel,
        content: Text(
          'Email accounts need the Buzz Masters backend (Supabase auth), '
          'which is not connected yet.',
          style: BmText.body(12),
        ),
      ),
    );
  }
}
