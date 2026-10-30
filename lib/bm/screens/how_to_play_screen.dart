import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../race/race_model.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';

/// About / How to Play. Every number comes from [RaceConfig], so the rules
/// shown here are the rules the race engine applies.
class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const c = kTurboRaceConfig;
    final sections = <(IconData, Color, String, String)>[
      (
        Icons.sports_score_rounded,
        BmColors.gold,
        'THE RACE',
        'Up to six racers line up on a neon track. Every question is a sprint: '
            'answer correctly to accelerate. The first racer to cover '
            '${c.distance} units takes the chequered flag and the race ends.',
      ),
      (
        Icons.timer_rounded,
        BmColors.cyan,
        'QUESTIONS',
        'Each multiple-choice question gives you '
            '${c.questionWindowMs ~/ 1000} seconds. You get one answer per '
            'question — once locked in it cannot be changed.',
      ),
      (
        Icons.bolt_rounded,
        BmColors.green,
        'SCORING',
        'Fast correct (within ${c.fastThresholdMs ~/ 1000}s): +${c.fastCorrectGain}\n'
            'Correct: +${c.correctGain}\n'
            'Wrong: −${c.wrongPenalty}\n'
            'No answer: −${c.timeoutPenalty}',
      ),
      (
        Icons.warning_amber_rounded,
        BmColors.red,
        'DANGER ZONE',
        'After a safe start of ${c.dangerFreeQuestions} questions, '
            '${c.dangerZoneMax} or less puts you in the red danger zone. Escape '
            'within ${c.dangerGraceQuestions} question or you are knocked out '
            'and spectate the rest of the race.',
      ),
      (
        Icons.emoji_events_rounded,
        BmColors.purple,
        'WINNING',
        'Finishers rank by finishing time, everyone else by distance. If no '
            'one finishes after ${c.maxQuestions} questions, the furthest '
            'racer wins. The top three take the podium.',
      ),
      (
        Icons.timer_outlined,
        BmColors.pink,
        'TIME TRIAL',
        'Race alone against the ghost of your best run and beat your time.',
      ),
    ];
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          const ArenaHeader(
              title: 'HOW TO PLAY', subtitle: 'TURBO TRIVIA RACE'),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: sections.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final (icon, color, title, body) = sections[i];
                return BmPanel(
                  color: color,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.18),
                          border: Border.all(color: color),
                        ),
                        child: Icon(icon, color: color, size: 21),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: BmText.display(16, color: color)),
                            const SizedBox(height: 4),
                            Text(body,
                                style: BmText.body(12.5,
                                    color: const Color(0xFFD5DAF5))),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          BmButton(
            label: 'GOT IT',
            icon: Icons.check_rounded,
            height: 50,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
