import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../game/practice_match.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/podium_card.dart';
import '../widgets/studio_background.dart';
import 'results_screen.dart';

/// Screen 8 — The studio: question display, buzzers, countdown and podiums.
class BmGameplayScreen extends StatefulWidget {
  const BmGameplayScreen({super.key});

  @override
  State<BmGameplayScreen> createState() => _BmGameplayScreenState();
}

class _BmGameplayScreenState extends State<BmGameplayScreen> {
  late final PracticeMatch _match;

  @override
  void initState() {
    super.initState();
    _match = PracticeMatch();
  }

  @override
  void dispose() {
    _match.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _match,
      builder: (context, _) {
        if (_match.isFinished) return BmResultsScreen(match: _match);
        if (_match.phase == MatchPhase.roundComplete) return _roundSummary();
        return _studio();
      },
    );
  }

  Widget _studio() {
    final q = _match.question;
    final answering = _match.phase == MatchPhase.answering;
    final revealed = _match.phase == MatchPhase.reveal;
    final canAnswer = answering && _match.activeIndex == 0;

    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              BmIconButton(
                icon: Icons.close_rounded,
                color: BmColors.pink,
                size: 36,
                tooltip: 'Quit match',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 8),
              RoundBadge(
                round: _match.config.number,
                title: _match.config.title,
                color:
                    _match.config.number == 3 ? BmColors.gold : BmColors.cyan,
              ),
              const Spacer(),
              Column(
                children: [
                  Text(
                    'QUESTION ${_match.questionNumber}/${_match.config.questions}',
                    style: BmText.label(9, color: BmColors.muted),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      for (var i = 0; i < _match.config.questions; i++)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _match.questionNumber - 1
                                ? BmColors.cyan
                                : Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              TimerRing(
                secondsLeft: _match.timeLeft,
                total: _match.total,
                size: 54,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  BmPanel(
                    color: BmColors.violet,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 18),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _chip(q?.category ?? '—', BmColors.cyan),
                            const SizedBox(width: 8),
                            _chip(q?.difficulty ?? '—', BmColors.gold),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          q?.text ?? '',
                          textAlign: TextAlign.center,
                          style: BmText.title(20).copyWith(height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (q != null)
                    for (var i = 0; i < q.options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AnswerTile(
                          letter: String.fromCharCode(65 + i),
                          text: q.options[i],
                          selected: _match.activeIndex == 0 &&
                              _match.selectedIndex == i,
                          correct: revealed && _match.revealedIndex == i,
                          wrong: revealed &&
                              _match.revealedIndex != i &&
                              _match.selectedIndex == i,
                          enabled: canAnswer,
                          onTap: () => _match.submitAnswer(i),
                        ),
                      ),
                  const SizedBox(height: 4),
                  _podiumStrip(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusLine(),
            textAlign: TextAlign.center,
            style: BmText.body(11.5, color: BmColors.muted),
          ),
          const SizedBox(height: 8),
          _buzzer(),
        ],
      ),
    );
  }

  String _statusLine() {
    switch (_match.phase) {
      case MatchPhase.buzzing:
        return _match.humanLockedOut
            ? 'You are locked out of this question'
            : 'Tap BUZZ to claim the question';
      case MatchPhase.answering:
        final active = _match.activeIndex;
        if (active == null) return 'Answering…';
        return active == 0
            ? 'Your answer — choose now'
            : '${_match.contestants[active].name} is answering…';
      case MatchPhase.reveal:
        return _match.lastResult ?? 'Answer revealed';
      case MatchPhase.roundComplete:
        return 'Round complete';
      case MatchPhase.finished:
        return 'Match complete';
    }
  }

  Widget _buzzer() {
    final enabled = _match.canBuzz;
    return GestureDetector(
      onTap: enabled ? _match.buzz : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.4,
        child: Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFFFF6B6B), Color(0xFFE02424), Color(0xFF7F1010)],
              stops: [0.0, 0.55, 1.0],
            ),
            border: Border.all(color: BmColors.gold, width: 4),
            boxShadow: [
              ...bmGlow(BmColors.red, blur: 34, opacity: enabled ? 0.7 : 0.2),
              BoxShadow(
                color: BmColors.gold.withValues(alpha: 0.35),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              'BUZZ',
              style: BmText.display(20, color: Colors.white)
                  .copyWith(letterSpacing: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _podiumStrip() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = ((constraints.maxWidth - 5 * 6) / 6).clamp(44.0, 96.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _match.contestants.length; i++)
              PodiumCard(
                color: _match.contestants[i].color,
                name: _match.contestants[i].name,
                score: _match.config.number == 3
                    ? '${_match.contestants[i].energy}*'
                    : '${_match.contestants[i].score}',
                width: width,
                height: width * 1.35,
                active: _match.activeIndex == i,
                eliminated: _match.contestants[i].eliminated,
              ),
          ],
        );
      },
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Text(text.toUpperCase(), style: BmText.label(8, color: color)),
    );
  }

  Widget _roundSummary() {
    final ranked = _match.contestants.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final isDuel = _match.config.number == 3;

    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        children: [
          Text(
            isDuel ? 'FINAL RESULT' : 'ROUND ${_match.config.number} COMPLETE',
            style: BmText.label(11, color: BmColors.cyan),
          ),
          const SizedBox(height: 6),
          Text(
            isDuel ? 'MASTER DUEL' : _match.config.title.toUpperCase(),
            style: BmText.display(26, color: BmColors.gold),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.separated(
              itemCount: ranked.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = ranked[i];
                return BmPanel(
                  color: c.eliminated
                      ? BmColors.muted
                      : BmColors.seatColors[_match.contestants.indexOf(c)],
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Text('${i + 1}',
                          style: BmText.display(16, color: BmColors.gold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          c.name,
                          style: BmText.title(14).copyWith(
                            decoration: c.eliminated
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      Text('${c.score}',
                          style: BmText.display(18, color: Colors.white)),
                      if (c.eliminated) ...[
                        const SizedBox(width: 8),
                        Text('OUT',
                            style: BmText.label(8, color: BmColors.red)),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          BmButton(
            label: 'NEXT ROUND',
            icon: Icons.fast_forward_rounded,
            height: 54,
            onPressed: _match.nextRound,
          ),
        ],
      ),
    );
  }
}
