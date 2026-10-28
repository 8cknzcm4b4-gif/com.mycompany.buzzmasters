import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/podium_card.dart';
import '../widgets/studio_background.dart';
import 'gameplay_screen.dart';

/// Screen 6 — Matchmaking. Seats are filled by explicitly labelled CPU
/// contestants because no networked matchmaking service is connected yet.
class BmMatchmakingScreen extends StatefulWidget {
  const BmMatchmakingScreen({super.key});

  @override
  State<BmMatchmakingScreen> createState() => _BmMatchmakingScreenState();
}

class _BmMatchmakingScreenState extends State<BmMatchmakingScreen> {
  static const _names = ['Alex', 'Sophie', 'Jordan', 'Emma', 'Liam', 'Chloe'];
  void _startPractice() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BmGameplayScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
      child: Column(
        children: [
          Row(
            children: [
              BmIconButton(
                icon: Icons.close_rounded,
                color: BmColors.pink,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              Column(
                children: [
                  Text('MATCHMAKING',
                      style: BmText.label(11, color: BmColors.cyan)),
                  const SizedBox(height: 2),
                  Text('THE QUALIFIER',
                      style: BmText.title(16)
                          .copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const Spacer(),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'QUICK PLAY',
                  style: BmText.display(24, color: BmColors.gold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Online matchmaking is not configured',
                  style: BmText.body(12, color: BmColors.muted),
                ),
                const SizedBox(height: 22),
                _seatGrid(),
                const SizedBox(height: 22),
                BmPanel(
                  color: BmColors.gold,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 14, color: BmColors.gold),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'No live players are being simulated. Connect a '
                          'Buzz Masters game server to enable online matches.',
                          style: BmText.body(10.5, color: BmColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          BmButton(
            label: 'TRY PRACTICE WITH CPU',
            icon: Icons.school_rounded,
            height: 52,
            fontSize: 13,
            onPressed: _startPractice,
          ),
          const SizedBox(height: 10),
          BmButton(
            label: 'BACK',
            style: BmButtonStyle.outline,
            height: 46,
            fontSize: 13,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _seatGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = ((constraints.maxWidth - 20) / 3).clamp(70.0, 110.0);
        return Wrap(
          spacing: 10,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < 6; i++)
              i == 0
                  ? PodiumCard(
                      color: BmColors.seatColors[i],
                      name: _names[i],
                      score: 'YOU',
                      width: width,
                      height: 108,
                      active: true,
                    )
                  : _emptySeat(width),
          ],
        );
      },
    );
  }

  Widget _emptySeat(double width) {
    return Container(
      width: width,
      height: 108,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_add_alt_1_rounded,
              color: Colors.white.withValues(alpha: 0.25), size: 22),
          const SizedBox(height: 6),
          Text('OPEN SEAT',
              style:
                  BmText.label(8, color: Colors.white.withValues(alpha: 0.3))),
        ],
      ),
    );
  }
}
