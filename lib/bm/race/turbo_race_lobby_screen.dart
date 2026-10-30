import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../online/join_game_screen.dart';
import '../online/online_lobby_screen.dart';
import '../online/online_race_service.dart';
import '../player/player_profile.dart';
import '../screens/how_to_play_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';
import 'race_model.dart';
import 'race_practice_screen.dart';
import 'time_trial_screen.dart';

/// Turbo Trivia Race lobby: six lit start podiums, the scoring rules and
/// every way into a race. Online hosting needs the game server, and the
/// lobby says so on the button instead of pretending.
class TurboRaceLobbyScreen extends StatelessWidget {
  const TurboRaceLobbyScreen({super.key, this.showBack = true});

  final bool showBack;

  void _push(BuildContext context, Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final online = OnlineRace.service.isConfigured;
    const c = kTurboRaceConfig;
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          ArenaHeader(
            title: 'TURBO TRIVIA RACE',
            subtitle: 'ANSWER FAST · KEEP MOVING',
            titleColor: BmColors.gold,
            showBack: showBack,
            trailing: BmIconButton(
              icon: Icons.settings_rounded,
              color: BmColors.gold,
              tooltip: 'Settings',
              onPressed: () => _push(context, const BmSettingsScreen()),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  ValueListenableBuilder<PlayerStats>(
                    valueListenable: PlayerProfileStore.current,
                    builder: (context, s, _) => _Podiums(player: s),
                  ),
                  const SizedBox(height: 12),
                  BmPanel(
                    color: BmColors.cyan,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _rule('+${c.fastCorrectGain}', 'FAST', BmColors.gold),
                        _rule('+${c.correctGain}', 'CORRECT', BmColors.green),
                        _rule('−${c.wrongPenalty}', 'WRONG', BmColors.red),
                        _rule('${c.distance}', 'TO FINISH', BmColors.cyan),
                        GestureDetector(
                          onTap: () => _push(context, const HowToPlayScreen()),
                          child: const Icon(Icons.help_outline_rounded,
                              color: BmColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  BmButton(
                    key: const ValueKey('lobby-practice'),
                    label: 'PRACTICE RACE',
                    icon: Icons.sports_score_rounded,
                    height: 56,
                    fontSize: 16,
                    onPressed: () => _push(context, const RacePracticeScreen()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: BmButton(
                          label: 'TIME TRIAL',
                          icon: Icons.timer_rounded,
                          style: BmButtonStyle.violet,
                          height: 50,
                          fontSize: 13,
                          onPressed: () =>
                              _push(context, const TimeTrialScreen()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: BmButton(
                          label: 'JOIN BY CODE',
                          icon: Icons.vpn_key_rounded,
                          style: BmButtonStyle.cyan,
                          height: 50,
                          fontSize: 13,
                          onPressed: () =>
                              _push(context, const JoinGameScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  BmButton(
                    key: const ValueKey('lobby-host'),
                    label: online
                        ? 'HOST ONLINE RACE'
                        : 'HOST ONLINE RACE · SERVER OFFLINE',
                    icon: online
                        ? Icons.public_rounded
                        : Icons.public_off_rounded,
                    style: BmButtonStyle.outline,
                    height: 46,
                    fontSize: 12,
                    onPressed: online ? () => _host(context) : null,
                  ),
                  if (!online)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Hosting and matchmaking need the Buzz Masters game '
                        'server, which this build is not connected to.',
                        textAlign: TextAlign.center,
                        style: BmText.body(11, color: BmColors.muted),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _host(BuildContext context) async {
    final result = await OnlineRace.service.createRoom();
    if (!context.mounted) return;
    final room = result.value;
    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: BmColors.panel,
        content: Text(result.message, style: BmText.body(12.5)),
      ));
      return;
    }
    _push(context, onlineRoomScreen(room));
  }

  // Each rule takes an equal share and scales down on narrow phones.
  Widget _rule(String value, String label, Color color) => Expanded(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            children: [
              Text(value, style: BmText.display(18, color: color)),
              Text(label, style: BmText.label(7.5)),
            ],
          ),
        ),
      );
}

/// Six start podiums; seat 1 is the player, the rest are the CPU racers a
/// practice race fills them with.
class _Podiums extends StatelessWidget {
  const _Podiums({required this.player});

  final PlayerStats player;

  static const _cpu = ['Alex', 'Sophie', 'Jordan', 'Emma', 'Liam'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 5 * 6) / 6;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 6; i++)
              _Podium(
                width: w,
                number: i + 1,
                color: i == 0 ? player.color : BmColors.seatColors[i],
                name: i == 0 ? player.name : _cpu[i - 1],
                tag: i == 0 ? 'YOU' : 'CPU',
                highlight: i == 0,
              ),
          ],
        );
      },
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({
    required this.width,
    required this.number,
    required this.color,
    required this.name,
    required this.tag,
    required this.highlight,
  });

  final double width;
  final int number;
  final Color color;
  final String name;
  final String tag;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        children: [
          Container(
            width: width * 0.78,
            height: width * 0.78,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.2),
              border: Border.all(
                  color: highlight ? BmColors.gold : color, width: 2),
              boxShadow: bmGlow(color, blur: 14, opacity: 0.6),
            ),
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: BmText.display(width * 0.32),
            ),
          ),
          const SizedBox(height: 4),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BmText.label(8, color: Colors.white, spacing: 0.3)),
          Text(tag,
              style: BmText.label(7,
                  color: highlight ? BmColors.gold : BmColors.muted)),
          const SizedBox(height: 4),
          // The lit lectern.
          Container(
            height: width * 1.15,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8), bottom: Radius.circular(3)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.85),
                  color.withValues(alpha: 0.35),
                  const Color(0xFF0A0E2C),
                ],
              ),
              border: Border.all(color: color, width: 1.2),
              boxShadow: bmGlow(color, blur: 18, opacity: 0.5),
            ),
            alignment: Alignment.center,
            child: Text('$number',
                style: BmText.display(width * 0.42,
                    color: Colors.white.withValues(alpha: 0.95))),
          ),
          Container(
            height: 5,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: BmColors.gold.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
