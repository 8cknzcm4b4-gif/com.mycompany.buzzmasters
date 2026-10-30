import 'dart:async';

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../online/join_game_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../backend/bm_supabase.dart';
import '../online/online_lobby_screen.dart';
import '../online/online_race_service.dart';
import '../race/race_practice_screen.dart';
import '../settings/bm_music.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';
import 'how_to_play_screen.dart';
import 'leaderboard_screen.dart';
import 'main_menu_screen.dart';
import 'settings_screen.dart';

/// Fade-and-rise page transition used between the main Buzz Masters screens.
Route<T> arenaRoute<T>(Widget screen) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => screen,
      transitionsBuilder: (_, a, __, child) {
        final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    );

/// Welcome: branding over the live arena, the main game actions, joining by
/// code, resuming a genuinely joined lobby, and account sign-in.
class BmWelcomeScreen extends StatefulWidget {
  const BmWelcomeScreen({super.key});

  @override
  State<BmWelcomeScreen> createState() => _BmWelcomeScreenState();
}

class _BmWelcomeScreenState extends State<BmWelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  late Future<RoomState?> _resumable = _findResumable();

  /// The server's record of the player's live room; never a local guess.
  static Future<RoomState?> _findResumable() async {
    if (!OnlineRace.service.isConfigured) return null;
    final result = await OnlineRace.service.liveRoom();
    return result.value;
  }

  bool _resuming = false;

  @override
  void initState() {
    super.initState();
    unawaited(BmMusic.start());
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  void _refreshResumable() {
    final next = _findResumable();
    setState(() {
      _resumable = next;
    });
  }

  Future<void> _open(Widget screen) async {
    unawaited(BmMusic.start());
    await Navigator.of(context).push(arenaRoute<void>(screen));
    if (mounted) _refreshResumable();
  }

  Future<void> _resume(RoomState room) async {
    setState(() => _resuming = true);
    // Re-check with the server: the race may have ended since the card showed.
    final result = await OnlineRace.service.roomState(room.roomId);
    if (!mounted) return;
    setState(() => _resuming = false);
    final live = result.value;
    if (live != null && live.isLive) {
      await _open(onlineRoomScreen(live));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(_snack(
        live == null ? result.message : 'That race has already finished.'));
    _refreshResumable();
  }

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
      intensity: 0.7,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              children: [
                _topBar(),
                const SizedBox(height: 4),
                _brand(),
                const SizedBox(height: 18),
                BmButton(
                  key: const ValueKey('welcome-play'),
                  label: 'PLAY NOW',
                  icon: Icons.play_arrow_rounded,
                  height: 60,
                  fontSize: 19,
                  onPressed: () => _open(const BmMainMenuScreen()),
                ),
                const SizedBox(height: 10),
                BmButton(
                  label: 'PRACTICE RACE',
                  icon: Icons.sports_score_rounded,
                  style: BmButtonStyle.violet,
                  height: 50,
                  fontSize: 15,
                  onPressed: () => _open(const RacePracticeScreen()),
                ),
                const SizedBox(height: 14),
                _joinCard(),
                FutureBuilder<RoomState?>(
                  future: _resumable,
                  builder: (context, snap) {
                    final session = snap.data;
                    if (session == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _resumeCard(session),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _signIn(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        BmIconButton(
          key: const ValueKey('welcome-info'),
          icon: Icons.info_outline_rounded,
          tooltip: 'How to play',
          color: BmColors.purple,
          onPressed: () => _open(const HowToPlayScreen()),
        ),
        const Spacer(),
        BmIconButton(
          key: const ValueKey('welcome-leaderboard'),
          icon: Icons.emoji_events_rounded,
          tooltip: 'Leaderboard',
          color: BmColors.gold,
          onPressed: () => _open(const LeaderboardScreen()),
        ),
        const SizedBox(width: 10),
        BmIconButton(
          key: const ValueKey('welcome-settings'),
          icon: Icons.settings_rounded,
          tooltip: 'Settings',
          onPressed: () => _open(const BmSettingsScreen()),
        ),
      ],
    );
  }

  Widget _brand() {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color:
                  BmColors.violet.withValues(alpha: 0.25 + 0.25 * _glow.value),
              blurRadius: 70,
              spreadRadius: 6,
            ),
          ],
        ),
        child: child,
      ),
      child: Column(
        children: [
          Image.asset('assets/images/bm_logo.png',
              width: 260, fit: BoxFit.contain),
          const SizedBox(height: 6),
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              colors: [BmColors.cyan, Colors.white, BmColors.gold],
            ).createShader(r),
            child: Text(
              'NEON TURBO QUIZ ARENA',
              style: BmText.display(17).copyWith(letterSpacing: 4),
            ),
          ),
          const SizedBox(height: 2),
          Text('Six racers. One finish line. Answer fast.',
              style: BmText.body(12, color: BmColors.muted)),
        ],
      ),
    );
  }

  Widget _joinCard() {
    return BmPanel(
      color: BmColors.cyan,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: BmGradients.cyan,
              boxShadow: bmGlow(BmColors.cyan, blur: 14, opacity: 0.5),
            ),
            child: const Icon(Icons.groups_rounded, color: BmColors.deep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('JOIN GAME', style: BmText.display(17)),
                Text('Race friends with a 6-digit code',
                    style: BmText.body(11.5, color: BmColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          BmButton(
            key: const ValueKey('welcome-get-started'),
            label: 'GET STARTED',
            style: BmButtonStyle.cyan,
            height: 40,
            fontSize: 12,
            expand: false,
            onPressed: () => _open(const JoinGameScreen()),
          ),
        ],
      ),
    );
  }

  Widget _resumeCard(RoomState session) {
    return GestureDetector(
      key: const ValueKey('welcome-resume'),
      onTap: _resuming ? null : () => _resume(session),
      child: BmPanel(
        color: BmColors.gold,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.history_rounded, color: BmColors.gold, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RESUME LAST SESSION',
                      style: BmText.label(11, color: Colors.white)),
                  Text('Race code ${session.code}',
                      style: BmText.body(12, color: BmColors.gold)),
                ],
              ),
            ),
            _resuming
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: BmColors.gold),
                  )
                : const Icon(Icons.play_circle_fill_rounded,
                    color: BmColors.gold, size: 30),
          ],
        ),
      ),
    );
  }

  Widget _signIn() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.15))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('ACCOUNT', style: BmText.label(9)),
            ),
            Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.15))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: BmButton(
                label: 'Apple',
                icon: Icons.apple,
                style: BmButtonStyle.white,
                height: 44,
                fontSize: 13,
                onPressed: () => _oauth(OAuthProvider.apple, 'Apple'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BmButton(
                label: 'Google',
                icon: Icons.g_mobiledata_rounded,
                style: BmButtonStyle.white,
                height: 44,
                fontSize: 13,
                onPressed: () => _oauth(OAuthProvider.google, 'Google'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BmButton(
                label: 'Email',
                icon: Icons.mail_rounded,
                style: BmButtonStyle.outline,
                height: 44,
                fontSize: 13,
                onPressed: _email,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<BmAccount?>(
          valueListenable: BmAuth.account,
          builder: (context, account, _) => Text(
            account == null || account.isGuest
                ? 'Playing as a guest — progress is saved on this device.'
                : 'Signed in${account.email == null ? '' : ' as ${account.email}'}.',
            key: const ValueKey('welcome-account-status'),
            textAlign: TextAlign.center,
            style: BmText.body(10.5, color: BmColors.muted),
          ),
        ),
      ],
    );
  }

  void _accountNotice(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(_snack(
      '$provider is not available yet: Buzz Masters accounts need the game '
      'server, which this build is not connected to. You can keep playing as '
      'a guest.',
    ));
  }

  Future<void> _oauth(OAuthProvider provider, String name) async {
    if (!BmAuth.available) return _accountNotice('Sign in with $name');
    final outcome = await BmAuth.signInWith(provider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(_snack(switch (outcome) {
      BmAuthOutcome.redirected => 'Continue signing in with $name…',
      _ => 'Sign in with $name failed. It must be enabled for this Buzz '
          'Masters project in the Supabase dashboard.',
    }));
  }

  Future<void> _email() async {
    if (!BmAuth.available) return _accountNotice('Email sign-in');
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BmColors.panel,
        title: Text('SIGN IN WITH EMAIL', style: BmText.display(18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          style: BmText.title(15),
          decoration: const InputDecoration(hintText: 'you@example.com'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
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
    if (address.isEmpty || !mounted) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(address)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(_snack('That does not look like an email address.'));
      return;
    }
    final outcome = await BmAuth.signInWithEmail(address);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(_snack(
        outcome == BmAuthOutcome.emailSent
            ? 'Check $address for your sign-in link.'
            : 'Could not send the sign-in link. Please try again.'));
  }

  SnackBar _snack(String text) => SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: BmColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: BmColors.cyan.withValues(alpha: 0.5)),
        ),
        content: Text(text, style: BmText.body(12.5)),
      );
}
