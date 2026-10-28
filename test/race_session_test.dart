import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:buzz_masters/bm/game/practice_match.dart';
import 'package:buzz_masters/bm/race/authority/race_protocol.dart';
import 'package:buzz_masters/bm/race/authority/race_server.dart';
import 'package:buzz_masters/bm/race/authority/race_session.dart';
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

void main() {
  test('session answers only when the server opens a question', () async {
    var now = 1000000;
    final server = RaceServer(
      matchId: 'match-1',
      racerIds: const ['you', 'bot'],
      questions: _questions,
      shuffleOptions: false,
      clock: () => now,
      random: Random(1),
    );
    final transport = LoopbackRaceTransport(server: server, racerId: 'you');
    final session = RaceSession(transport: transport, racerId: 'you');

    expect(session.canAnswer, isFalse);
    expect(session.requestAnswer(0), isFalse);

    server.join('bot');
    server.start();
    now += 3000;
    server.tick();
    await pumpEventQueue();

    expect(session.snapshot?.phase, RacePhase.questionActive);
    expect(session.canAnswer, isTrue);

    expect(session.requestAnswer(0), isTrue);
    expect(session.requestAnswer(0), isFalse, reason: 'local guard');
    await pumpEventQueue();

    expect(session.lastNotice.value?.accepted, isTrue);
    expect(session.snapshot?.racerFor('you')?.progress, 15);

    await session.dispose();
    await transport.close();
    await server.dispose();
  });

  test('the answer guard resets when the next question opens', () async {
    var now = 1000000;
    final server = RaceServer(
      matchId: 'match-1',
      racerIds: const ['you', 'bot'],
      questions: _questions,
      shuffleOptions: false,
      clock: () => now,
      random: Random(1),
    );
    final transport = LoopbackRaceTransport(server: server, racerId: 'you');
    final session = RaceSession(transport: transport, racerId: 'you');
    server.join('bot');
    server.start();
    now += 3000;
    server.tick();
    await pumpEventQueue();

    session.requestAnswer(0);
    await pumpEventQueue();
    expect(session.canAnswer, isFalse);

    now += 8000;
    server.tick();
    now += 1500;
    server.tick();
    await pumpEventQueue();

    expect(session.snapshot?.question?.index, 1);
    expect(session.canAnswer, isTrue);

    await session.dispose();
    await transport.close();
    await server.dispose();
  });

  test('a forged command cannot move a racer', () async {
    var now = 1000000;
    final server = RaceServer(
      matchId: 'match-1',
      racerIds: const ['you', 'bot'],
      questions: _questions,
      shuffleOptions: false,
      clock: () => now,
      random: Random(1),
    );
    final transport = LoopbackRaceTransport(server: server, racerId: 'you');
    final session = RaceSession(transport: transport, racerId: 'you');
    server.join('bot');
    server.start();
    now += 3000;
    server.tick();
    await pumpEventQueue();

    final before = session.snapshot!.racerFor('you')!.progress;
    transport.send(
      const SubmitAnswer(racerId: 'you', questionIndex: 42, optionIndex: 0),
    );
    await pumpEventQueue();

    expect(
      session.lastNotice.value?.status,
      RaceAnswerStatus.rejectedOutOfPhase,
    );
    expect(session.snapshot!.racerFor('you')!.progress, before);
    expect(session.canAnswer, isTrue);

    await session.dispose();
    await transport.close();
    await server.dispose();
  });
}
