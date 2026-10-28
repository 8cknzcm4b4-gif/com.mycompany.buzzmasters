import 'package:flutter_test/flutter_test.dart';
import 'package:buzz_masters/bm/race/race_model.dart';

RaceModel _race({List<String> ids = const ['a', 'b', 'c'], int start = 0}) {
  return RaceModel(
    config: const RaceConfig(),
    racers: [for (final id in ids) RacerProgress(id: id, progress: start)],
  );
}

RaceModel _racing({int start = 0}) {
  return _race(start: start).startCountdown().go().openQuestion();
}

void main() {
  test('speed status follows the most recent answer', () {
    var race = _racing();
    race = race
        .applyAnswer(racerId: 'a', correct: true, responseMs: 1000, atMs: 1000)
        .applyAnswer(racerId: 'b', correct: true, responseMs: 5000, atMs: 5000)
        .applyAnswer(racerId: 'c', correct: false, responseMs: 1000, atMs: 1000);
    expect(race.racers.firstWhere((r) => r.id == 'a').speed, SpeedStatus.fast);
    expect(
      race.racers.firstWhere((r) => r.id == 'b').speed,
      SpeedStatus.cruising,
    );
    expect(
      race.racers.firstWhere((r) => r.id == 'c').speed,
      SpeedStatus.stopped,
    );

    final afterTimeout = race.applyTimeout(answeredIds: {'a'}, atMs: 8000);
    expect(
      afterTimeout.racers.firstWhere((r) => r.id == 'b').speed,
      SpeedStatus.stopped,
    );
  });

  test('positions rank every racer once, leader first', () {
    final race = _racing(start: 50)
        .applyAnswer(racerId: 'c', correct: true, responseMs: 1000, atMs: 1000);
    final positions = race.positions;
    expect(race.positionOf('c'), 1);
    expect(positions.values.toSet(), {1, 2, 3});
    expect(positions.length, 3);
  });

  test('an eliminated racer spectates until the race ends', () {
    var race = RaceModel(
      config: const RaceConfig(),
      racers: const [
        RacerProgress(id: 'a', progress: 5),
        RacerProgress(id: 'b', progress: 40),
        RacerProgress(id: 'c', progress: 40),
      ],
    ).startCountdown().go().openQuestion();
    for (var i = 0; i < 2; i++) {
      race = race
          .applyTimeout(answeredIds: {'b', 'c'}, atMs: 8000 * (i + 1))
          .resolveQuestion()
          .openQuestion();
    }
    expect(race.racers.firstWhere((r) => r.id == 'a').eliminated, isTrue);
    expect(race.spectating('a'), isTrue);
    expect(race.spectating('b'), isFalse);
    expect(race.finish().spectating('a'), isFalse);
  });

  test('danger zone warns first, then eliminates after grace', () {
    var race = _racing(start: 5);
    race = race.applyTimeout(answeredIds: {'b', 'c'}, atMs: 8000);
    race = race.resolveQuestion();
    final a1 = race.racers.firstWhere((r) => r.id == 'a');
    expect(race.inDangerZone('a'), isTrue);
    expect(a1.dangerStreak, 1);
    expect(a1.eliminated, isFalse);

    race = race.openQuestion();
    race = race.applyTimeout(answeredIds: {'b', 'c'}, atMs: 16000);
    race = race.resolveQuestion();
    final a2 = race.racers.firstWhere((r) => r.id == 'a');
    expect(a2.eliminated, isTrue);
    expect(race.rankings.last.id, 'a');
  });

  test('leaving the danger zone resets the warning streak', () {
    var race = _racing(start: 5);
    race = race.applyTimeout(answeredIds: {'b', 'c'}, atMs: 8000);
    race = race.resolveQuestion();
    expect(race.racers.firstWhere((r) => r.id == 'a').dangerStreak, 1);

    race = race.openQuestion();
    race = race.applyAnswer(
      racerId: 'a',
      correct: true,
      responseMs: 1000,
      atMs: 9000,
    );
    race = race.applyTimeout(answeredIds: {'a', 'b', 'c'}, atMs: 9000);
    race = race.resolveQuestion();
    final a = race.racers.firstWhere((r) => r.id == 'a');
    expect(a.progress, greaterThan(10));
    expect(a.dangerStreak, 0);
    expect(a.eliminated, isFalse);
  });

  test('question cap ends the race when nobody has finished', () {
    final race0 = RaceModel(
      config: const RaceConfig(maxQuestions: 1),
      racers: [for (final id in ['a', 'b']) RacerProgress(id: id)],
    ).startCountdown().go().openQuestion();
    final race = race0
        .applyTimeout(answeredIds: {'a', 'b'}, atMs: 8000)
        .resolveQuestion();
    expect(race.phase, RacePhase.results);
    expect(race.questionsAsked, 1);
  });

  test('lifecycle moves waiting, countdown, racing, question', () {
    var race = _race();
    expect(race.phase, RacePhase.waiting);
    race = race.startCountdown();
    expect(race.phase, RacePhase.countdown);
    race = race.go();
    expect(race.phase, RacePhase.racing);
    race = race.openQuestion();
    expect(race.phase, RacePhase.questionActive);
  });

  test('correct answer adds normal progress, fast answer adds more', () {
    final race = _racing();
    final slow = race.applyAnswer(
      racerId: 'a',
      correct: true,
      responseMs: 5000,
      atMs: 5000,
    );
    final fast = race.applyAnswer(
      racerId: 'a',
      correct: true,
      responseMs: 1000,
      atMs: 1000,
    );
    expect(slow.racers.first.progress, 10);
    expect(fast.racers.first.progress, 15);
  });

  test('wrong answer penalises and never drops below zero', () {
    final race = _racing(start: 2).applyAnswer(
      racerId: 'a',
      correct: false,
      responseMs: 1000,
      atMs: 1000,
    );
    expect(race.racers.first.progress, 0);
  });

  test('timeout penalises only racers who did not answer', () {
    final race = _racing(start: 20).applyTimeout(
      answeredIds: {'a'},
      atMs: 8000,
    );
    expect(race.racers.firstWhere((r) => r.id == 'a').progress, 20);
    expect(race.racers.firstWhere((r) => r.id == 'b').progress, 17);
    expect(race.phase, RacePhase.answerSubmitted);
  });

  test('danger zone is reported at or below the threshold', () {
    final race = _racing(start: 10);
    expect(race.inDangerZone('a'), isTrue);
    final safe = _racing(start: 11);
    expect(safe.inDangerZone('a'), isFalse);
  });

  test('reaching the distance records finish time and caps progress', () {
    final race = _racing(start: 95).applyAnswer(
      racerId: 'a',
      correct: true,
      responseMs: 1000,
      atMs: 4321,
    );
    final racer = race.racers.firstWhere((r) => r.id == 'a');
    expect(racer.progress, 100);
    expect(racer.finished, isTrue);
    expect(racer.finishedAtMs, 4321);
  });

  test('rankings put finishers first by time, then progress, then id', () {
    var race = _race(ids: ['a', 'b', 'c', 'd']).startCountdown().go();
    race = race
        .openQuestion()
        .applyAnswer(racerId: 'a', correct: true, responseMs: 1, atMs: 900)
        .applyAnswer(racerId: 'b', correct: true, responseMs: 1, atMs: 500)
        .applyAnswer(racerId: 'c', correct: true, responseMs: 9000, atMs: 900)
        .applyAnswer(racerId: 'd', correct: false, responseMs: 1, atMs: 900);
    // No one has finished. a and b tie at 15 (fast), so id breaks the tie.
    final order = race.rankings.map((r) => r.id).toList();
    expect(order, ['a', 'b', 'c', 'd']);
  });

  test('race ends once every racer has finished or been eliminated', () {
    final race = _racing(start: 100).applyAnswer(
      racerId: 'a',
      correct: true,
      responseMs: 1,
      atMs: 10,
    );
    expect(race.resolveQuestion().finishIfDone().phase, RacePhase.racing);
  });

  test('finished racer ignores further answers', () {
    final race = _racing(start: 100).applyAnswer(
      racerId: 'a',
      correct: true,
      responseMs: 1,
      atMs: 10,
    );
    final again = race
        .resolveQuestion()
        .openQuestion()
        .applyAnswer(racerId: 'a', correct: true, responseMs: 1, atMs: 20);
    expect(again.racers.first.finishedAtMs, 10);
    expect(again.racers.first.progress, 100);
  });

  test('finish ends the race as soon as one racer has finished', () {
    final race = RaceModel(
      config: const RaceConfig(),
      racers: const [
        RacerProgress(id: 'a', progress: 100, finishedAtMs: 10),
        RacerProgress(id: 'b', progress: 40),
      ],
      phase: RacePhase.racing,
    );
    expect(race.finishIfDone().phase, RacePhase.racing);
    expect(race.finish().phase, RacePhase.results);
  });
}
