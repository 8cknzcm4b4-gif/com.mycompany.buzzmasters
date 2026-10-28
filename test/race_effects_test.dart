import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buzz_masters/bm/race/countdown_badge.dart';
import 'package:buzz_masters/bm/race/elimination_flash.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('countdown shows the seconds left, then GO', (tester) async {
    await tester.pumpWidget(_wrap(const RaceCountdown(secondsLeft: 3)));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('GET READY'), findsOneWidget);

    await tester.pumpWidget(_wrap(const RaceCountdown(secondsLeft: 2)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2'), findsOneWidget);

    await tester.pumpWidget(_wrap(const RaceCountdown(secondsLeft: 0)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('GO!'), findsOneWidget);
    expect(find.text('RACE!'), findsOneWidget);
  });

  testWidgets('elimination flash animates its lane and settles', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EliminationFlash(
          child: SizedBox(height: 40, child: Text('Alex OUT')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Alex OUT'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alex OUT'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(find.text('Alex OUT'), findsOneWidget);
  });
}
