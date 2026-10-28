import 'package:flutter_test/flutter_test.dart';

import 'package:buzz_masters/bm/game/practice_match.dart';

int _wrongOf(PracticeMatch m) => (m.correctIndex + 1) % 4;

void main() {
  group('Round 1 buzzer', () {
    test('wrong answer costs points and locks the human out', () {
      final m = PracticeMatch.forTesting();
      addTearDown(m.dispose);

      m.buzz();
      expect(m.phase, MatchPhase.answering);
      m.submitAnswer(_wrongOf(m));

      expect(m.human.score, -1);
      expect(m.phase, MatchPhase.reveal);

      // After the reveal the buzzer reopens, but the human stays locked out.
      m.advanceSecondsForTesting(1.5);
      expect(m.phase, MatchPhase.buzzing);
      expect(m.humanLockedOut, isTrue);
      expect(m.canBuzz, isFalse);
    });

    test('answer timeout carries no penalty', () {
      final m = PracticeMatch.forTesting();
      addTearDown(m.dispose);

      m.buzz();
      m.advanceSecondsForTesting(10.1);

      expect(m.human.score, 0);
      expect(m.human.wrong, 0);
      expect(m.phase, MatchPhase.reveal);
      expect(m.lastResult, contains('timed out'));
    });

    test('correct answer scores the round points', () {
      final m = PracticeMatch.forTesting();
      addTearDown(m.dispose);

      m.buzz();
      m.submitAnswer(m.correctIndex);

      expect(m.human.score, 2);
      expect(m.human.correct, 1);
    });
  });

  group('Round 3 Master Duel', () {
    PracticeMatch duel({bool suddenDeath = false}) => PracticeMatch.forTesting(
          startingRound: 3,
          activeContestantIndices: {0, 1},
          startingSuddenDeath: suddenDeath,
        );

    test('correct answer drains opponent energy and does not finish early', () {
      final m = duel();
      addTearDown(m.dispose);

      m.buzz();
      m.submitAnswer(m.correctIndex);

      expect(m.contestants[1].energy, 4);
      expect(m.phase, MatchPhase.reveal);

      m.advanceSecondsForTesting(2.0);
      expect(m.phase, MatchPhase.buzzing);
      expect(m.active.length, 2);
      expect(m.isFinished, isFalse);
    });

    test('sudden death correct answer eliminates opponent and finishes', () {
      final m = duel(suddenDeath: true);
      addTearDown(m.dispose);

      m.buzz();
      m.submitAnswer(m.correctIndex);

      expect(m.contestants[1].eliminated, isTrue);
      m.advanceSecondsForTesting(2.0);
      expect(m.isFinished, isTrue);
      expect(m.winner, m.human);
    });
  });
}
