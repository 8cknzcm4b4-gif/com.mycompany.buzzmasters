import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buzz_masters/bm/game/practice_match.dart';
import 'package:buzz_masters/bm/race/race_model.dart';
import 'package:buzz_masters/bm/race/time_trial_screen.dart';
import 'package:buzz_masters/bm/race/time_trial_store.dart';
import 'package:buzz_masters/bm/widgets/bm_panel.dart';

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
];

void main() {
  testWidgets('a finished run saves a ghost and offers a rematch',
      (tester) async {
    final store = MemoryTimeTrialStore();
    await tester.pumpWidget(
      MaterialApp(
        home: TimeTrialScreen(
          config: const RaceConfig(
            distance: 10,
            correctGain: 10,
            fastCorrectGain: 10,
            dangerZoneMax: -1,
          ),
          questions: _questions,
          store: store,
          random: Random(1),
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(AnswerTile), findsNWidgets(2));

    await tester.tap(find.byType(AnswerTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('RACE AGAIN'), findsOneWidget);
    expect(find.text('NEW BEST'), findsOneWidget);
    expect(store.saveCount, 1);
    expect(store.best, isNotNull);
    expect(store.best!.distance, 10);
  });
}
