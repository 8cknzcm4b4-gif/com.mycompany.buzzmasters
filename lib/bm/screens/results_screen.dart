import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../game/practice_match.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';

/// Screens 9-12 — elimination outcome, victory and personal match stats.
class BmResultsScreen extends StatelessWidget {
  const BmResultsScreen({super.key, required this.match});

  final PracticeMatch match;

  @override
  Widget build(BuildContext context) {
    final winner = match.winner ?? match.contestants.first;
    final human = match.human;
    final humanWon = winner == human;
    final rankings = _rankings(winner);
    final answered = human.correct + human.wrong;
    final accuracy =
        answered == 0 ? 0 : ((human.correct / answered) * 100).round();

    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        children: [
          Text('BUZZ MASTERS', style: BmText.label(10, color: BmColors.cyan)),
          const SizedBox(height: 6),
          Text(
            humanWon
                ? 'YOU ARE THE BUZZ MASTER'
                : '${winner.name.toUpperCase()} WINS',
            textAlign: TextAlign.center,
            style: BmText.display(24, color: BmColors.gold),
          ),
          const SizedBox(height: 14),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: BmGradients.gold,
              boxShadow: bmGlow(BmColors.gold, blur: 40, opacity: 0.55),
            ),
            child: const Icon(Icons.emoji_events_rounded,
                color: Color(0xFF3A2400), size: 48),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < rankings.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: BmPanel(
                        color: i == 0 ? BmColors.gold : BmColors.panelEdge,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        child: Row(
                          children: [
                            Text('${i + 1}',
                                style:
                                    BmText.display(15, color: BmColors.gold)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                rankings[i].name,
                                style: BmText.title(13).copyWith(
                                  fontWeight: rankings[i] == human
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              '${rankings[i].correct} ✓ / ${rankings[i].wrong} ✗',
                              style: BmText.body(10, color: BmColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  BmPanel(
                    color: BmColors.cyan,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _stat('PLACING', '#${rankings.indexOf(human) + 1}'),
                        _stat('CORRECT', '${human.correct}'),
                        _stat('ACCURACY', '$accuracy%'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Practice match only — no XP, ranking or leaderboard '
                    'changes were saved because no backend is connected.',
                    textAlign: TextAlign.center,
                    style: BmText.body(10, color: BmColors.muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          BmButton(
            label: 'REMATCH',
            icon: Icons.replay_rounded,
            height: 52,
            onPressed: match.restart,
          ),
          const SizedBox(height: 8),
          BmButton(
            label: 'RETURN HOME',
            style: BmButtonStyle.outline,
            height: 48,
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
    );
  }

  List<Contestant> _rankings(Contestant winner) {
    final others = match.contestants.where((c) => c != winner).toList()
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return [winner, ...others];
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(value, style: BmText.display(20, color: Colors.white)),
        const SizedBox(height: 2),
        Text(label, style: BmText.label(8, color: BmColors.cyan)),
      ],
    );
  }
}
