import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzz_masters/bm/race/race_practice_screen.dart';
import 'package:buzz_masters/bm/race/time_trial_screen.dart';
import 'package:buzz_masters/bm/race/time_trial_store.dart';
import 'package:buzz_masters/bm/screens/settings_screen.dart';
import 'package:buzz_masters/bm/settings/bm_audio_settings.dart';
import 'package:buzz_masters/bm/widgets/bm_panel.dart';

List<String> _options(WidgetTester tester) => tester
    .widgetList<AnswerTile>(find.byType(AnswerTile))
    .map((tile) => tile.text)
    .toList();

Future<void> _openSettingsFromRace(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_rounded));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(BmSettingsScreen), findsOneWidget);
}

Future<void> _closeSettings(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BmSettingsScreen),
      matching: find.byIcon(Icons.arrow_back_rounded),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(BmSettingsScreen), findsNothing);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BmAudioSettings.resetForTests();
  });

  testWidgets('a practice question is held while settings is open',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: RacePracticeScreen(random: Random(7))),
    );
    await tester.pump(const Duration(seconds: 4));

    final before = _options(tester);
    expect(before, hasLength(4));

    await _openSettingsFromRace(tester);

    // Far longer than the 8s question window.
    await tester.pump(const Duration(seconds: 20));

    await _closeSettings(tester);

    expect(_options(tester), before);
  });

  testWidgets('a time trial question is held while settings is open',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimeTrialScreen(
          store: MemoryTimeTrialStore(),
          random: Random(3),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));

    final before = _options(tester);
    expect(before, hasLength(4));

    await _openSettingsFromRace(tester);
    await tester.pump(const Duration(seconds: 20));
    await _closeSettings(tester);

    expect(_options(tester), before);
  });
}
