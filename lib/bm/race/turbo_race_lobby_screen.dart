import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../screens/settings_screen.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';
import 'race_practice_screen.dart';
import 'time_trial_screen.dart';

/// Turbo Trivia Race lobby. Shows six seats. No networked matchmaking or
/// friend invites exist yet, so those actions are disabled and labelled.
class TurboRaceLobbyScreen extends StatelessWidget {
  const TurboRaceLobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  'TURBO TRIVIA RACE',
                  textAlign: TextAlign.center,
                  style: BmText.display(18, color: BmColors.gold),
                ),
              ),
              SizedBox(
                width: 48,
                child: Center(
                  child: BmIconButton(
                    icon: Icons.settings_rounded,
                    color: BmColors.gold,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BmSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Answer Fast. Keep Moving. Reach the Show.',
            style: BmText.body(12),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.4,
              children: [
                for (var i = 0; i < 6; i++) _SeatCard(number: i + 1),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const BmButton(
            label: 'PLAY RACE (ONLINE UNAVAILABLE)',
            icon: Icons.public_off_rounded,
            onPressed: null,
            style: BmButtonStyle.outline,
          ),
          const SizedBox(height: 8),
          const BmButton(
            label: 'RACE WITH FRIENDS (UNAVAILABLE)',
            icon: Icons.people_alt_rounded,
            onPressed: null,
            style: BmButtonStyle.outline,
          ),
          const SizedBox(height: 8),
          BmButton(
            label: 'PRACTICE RACE',
            icon: Icons.school_rounded,
            style: BmButtonStyle.cyan,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RacePracticeScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          BmButton(
            label: 'TIME TRIAL',
            icon: Icons.timer_rounded,
            style: BmButtonStyle.outline,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TimeTrialScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SeatCard extends StatelessWidget {
  const _SeatCard({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return BmPanel(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            child: Text('$number', style: BmText.title(12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Open seat',
              style: BmText.label(9, color: BmColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
