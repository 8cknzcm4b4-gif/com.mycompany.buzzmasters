import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buzz_masters/bm/race/finish_confetti.dart';
import 'package:buzz_masters/bm/race/race_practice_screen.dart';
import 'package:buzz_masters/bm/widgets/bm_panel.dart';

void main() {
  testWidgets('practice race counts down, takes an answer and ends with results',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: RacePracticeScreen(random: Random(7))),
    );

    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(AnswerTile), findsNWidgets(4));

    await tester.tap(find.byType(AnswerTile).first);
    await tester.pump();
    for (var i = 0; i < 40 && find.textContaining('Answer:').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.textContaining('Answer:'), findsOneWidget);

    for (var i = 0; i < 4000 && find.text('RESULTS').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('RESULTS'), findsOneWidget);
    expect(find.text('BACK TO LOBBY'), findsOneWidget);
    expect(find.byType(FinishConfetti), findsOneWidget);
  });
}
