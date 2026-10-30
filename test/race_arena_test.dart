import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buzz_masters/bm/race/race_arena.dart';
import 'package:buzz_masters/bm/race/race_model.dart';

const _ids = ['you', 'alex', 'sophie', 'jordan', 'emma', 'liam'];

List<ArenaRacer> _racers(List<int> progress) => [
      for (var i = 0; i < _ids.length; i++)
        ArenaRacer(
          id: _ids[i],
          name: _ids[i].toUpperCase(),
          color: Colors.primaries[i],
          progress: progress[i],
          speed: SpeedStatus.cruising,
          isPlayer: i == 0,
        ),
    ];

Map<String, int> _positions(List<int> progress) {
  final order = [..._ids]..sort(
      (a, b) => progress[_ids.indexOf(b)].compareTo(progress[_ids.indexOf(a)]));
  return {for (var i = 0; i < order.length; i++) order[i]: i + 1};
}

Widget _host(List<int> progress,
        {bool finished = false, VoidCallback? onOvertake}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          height: 340,
          child: RaceArena(
            distance: 100,
            positions: _positions(progress),
            running: true,
            finished: finished,
            hudLabel: 'Q 2 / 30',
            racers: _racers(progress),
            onPlayerOvertake: onOvertake,
          ),
        ),
      ),
    );

void main() {
  testWidgets('the standings board lists all six racers in position order',
      (tester) async {
    await tester.pumpWidget(_host([10, 40, 30, 20, 5, 0]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('POSITION'), findsOneWidget);
    for (final id in _ids) {
      expect(find.text(id.toUpperCase()), findsOneWidget);
    }
    final alexTop = tester.getTopLeft(find.text('ALEX')).dy;
    final youTop = tester.getTopLeft(find.text('YOU')).dy;
    expect(alexTop, lessThan(youTop));
  });

  testWidgets('an overtake moves the row up and calls out the player',
      (tester) async {
    var overtakes = 0;
    await tester.pumpWidget(
        _host([10, 40, 30, 20, 5, 0], onOvertake: () => overtakes++));
    await tester.pump(const Duration(milliseconds: 100));
    final before = tester.getTopLeft(find.text('YOU')).dy;

    await tester.pumpWidget(
        _host([45, 40, 30, 20, 5, 0], onOvertake: () => overtakes++));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('OVERTAKE!  P1'), findsOneWidget);
    expect(overtakes, 1);

    await tester.pump(const Duration(milliseconds: 700));
    final after = tester.getTopLeft(find.text('YOU')).dy;
    expect(after, lessThan(before));

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('OVERTAKE!  P1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('final stretch and finish flash appear at the right moments',
      (tester) async {
    await tester.pumpWidget(_host([80, 40, 30, 20, 5, 0]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('FINAL STRETCH'), findsOneWidget);

    await tester.pumpWidget(_host([100, 40, 30, 20, 5, 0], finished: true));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('FINISH!'), findsOneWidget);
    expect(find.text('FINAL STRETCH'), findsNothing);
  });
}
