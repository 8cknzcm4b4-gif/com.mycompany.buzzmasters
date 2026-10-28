import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:buzz_masters/bm/game/practice_match.dart';
import 'package:buzz_masters/bm/race/authority/race_protocol.dart';
import 'package:buzz_masters/bm/race/authority/race_server.dart';
import 'package:buzz_masters/bm/race/race_model.dart';

const _questions = [
  QuizQuestion(
    id: 'q1',
    category: 'Science',
    difficulty: 'Easy',
    text: 'Which option is first?',
    options: ['Alpha', 'Beta'],
    correctIndex: 0,
    explanation: 'Alpha is first.',
  ),
  QuizQuestion(
    id: 'q2',
    category: 'Science',
    difficulty: 'Easy',
    text: 'Which option is second?',
    options: ['Gamma', 'Delta'],
    correctIndex: 1,
    explanation: 'Delta is second.',
  ),
];

class _Clock {
  int ms = 1000000;
  int call() => ms;
}

({RaceServer server, _Clock clock}) _server({
  List<String> racers = const ['a', 'b'],
  RaceConfig config = const RaceConfig(),
}) {
  final clock = _Clock();
  final server = RaceServer(
    matchId: 'match-1',
    racerIds: racers,
    questions: _questions,
    config: config,
    shuffleOptions: false,
    clock: clock.call,
    random: Random(1),
  );
  for (final id in racers) {
    server.join(id);
  }
  return (server: server, clock: clock);
}

void _start(RaceServer server, _Clock clock) {
  server.start();
  clock.ms += 3000;
  server.tick();
}

void main() {
  test('answers before the race start are refused', () {
    final s = _server();
    final notice = s.server.handle(
      const SubmitAnswer(racerId: 'a', questionIndex: 0, optionIndex: 0),
    );
    expect(notice.status, RaceAnswerStatus.rejectedOutOfPhase);
    expect(notice.accepted, isFalse);
  });

  test('racers outside the roster are refused', () {
    final s = _server();
    _start(s.server, s.clock);
    final notice = s.server.handle(
      const SubmitAnswer(racerId: 'intruder', questionIndex: 0, optionIndex: 0),
    );
    expect(notice.status, RaceAnswerStatus.rejectedUnknownRacer);
  });

  test('duplicate answers are refused and move the racer once', () {
    final s = _server();
    _start(s.server, s.clock);

    final first = s.server.handle(
      const SubmitAnswer(racerId: 'a', questionIndex: 0, optionIndex: 0),
    );
    final second = s.server.handle(
      const SubmitAnswer(racerId: 'a', questionIndex: 0, optionIndex: 0),
    );

    expect(first.accepted, isTrue);
    expect(first.correct, isTrue);
    expect(first.progress, 15);
    expect(second.status, RaceAnswerStatus.rejectedDuplicate);
    expect(s.server.snapshot().racerFor('a')!.progress, 15);
  });

  test('answers after the deadline are refused', () {
    final s = _server();
    _start(s.server, s.clock);
    s.clock.ms += 8001;

    final notice = s.server.handle(
      const SubmitAnswer(racerId: 'a', questionIndex: 0, optionIndex: 0),
    );

    expect(notice.status, RaceAnswerStatus.rejectedLate);
    expect(s.server.snapshot().racerFor('a')!.progress, 0);
  });

  test('the server judges the answer, not the client', () {
    final s = _server();
    _start(s.server, s.clock);

    final invalid = s.server.handle(
      const SubmitAnswer(racerId: 'a', questionIndex: 0, optionIndex: 9),
    );
    final wrong = s.server.handle(
      const SubmitAnswer(racerId: 'b', questionIndex: 0, optionIndex: 1),
    );

    expect(invalid.status, RaceAnswerStatus.rejectedInvalidOption);
    expect(wrong.accepted, isTrue);
    expect(wrong.correct, isFalse);
    expect(wrong.progress, 0);
  });

  test('snapshots never carry the correct answer', () {
    final s = _server();
    _start(s.server, s.clock);

    final json = jsonEncode(s.server.snapshot().toJson());

    expect(json.contains('correctIndex'), isFalse);
    expect(json.contains('explanation'), isFalse);
    expect(json.contains('Alpha is first'), isFalse);
    expect(json.contains('Which option is first?'), isTrue);
  });

  test('the server deadline closes the window and opens the next question', () {
    final s = _server();
    _start(s.server, s.clock);
    expect(s.server.snapshot().question!.index, 0);

    s.clock.ms += 8000;
    s.server.tick();
    expect(s.server.state.questionsAsked, 1);
    expect(s.server.snapshot().phase, RacePhase.racing);

    s.clock.ms += 1500;
    s.server.tick();
    expect(s.server.snapshot().phase, RacePhase.questionActive);
    expect(s.server.snapshot().question!.index, 1);
  });

  test('the first finisher ends the race', () {
    final s = _server(
      config: const RaceConfig(
        distance: 10,
        correctGain: 10,
        fastCorrectGain: 10,
      ),
    );
    _start(s.server, s.clock);

    final notice = s.server.handle(
      const SubmitAnswer(racerId: 'a', questionIndex: 0, optionIndex: 0),
    );
    final snapshot = s.server.snapshot();

    expect(notice.accepted, isTrue);
    expect(snapshot.phase, RacePhase.results);
    expect(snapshot.ranking.first, 'a');
    expect(snapshot.racerFor('a')!.finished, isTrue);
  });

  test('command and snapshot survive a wire round trip', () {
    const answer = SubmitAnswer(
      racerId: 'a',
      questionIndex: 2,
      optionIndex: 3,
    );
    final decoded = RaceCommand.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(answer.toJson())) as Map,
      ),
    );
    expect(decoded, isA<SubmitAnswer>());
    expect((decoded as SubmitAnswer).questionIndex, 2);
    expect(decoded.optionIndex, 3);

    final s = _server();
    _start(s.server, s.clock);
    final snapshot = s.server.snapshot();
    final round = RaceSnapshot.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map,
      ),
    );

    expect(round.matchId, snapshot.matchId);
    expect(round.phase, snapshot.phase);
    expect(round.question!.id, snapshot.question!.id);
    expect(round.racers.length, snapshot.racers.length);
    expect(round.ranking, snapshot.ranking);
  });
}
