import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzz_masters/bm/screens/settings_screen.dart';
import 'package:buzz_masters/bm/settings/bm_audio_settings.dart';

/// The studio backdrop animates forever, so settle a few frames instead of
/// waiting for the tree to go quiet.
Future<void> _showSettings(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: BmSettingsScreen()));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BmAudioSettings.resetForTests();
  });

  testWidgets('switches mirror the saved preferences', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      BmAudioSettings.soundKey: false,
      BmAudioSettings.hapticsKey: true,
      BmAudioSettings.musicKey: false,
    });
    BmAudioSettings.resetForTests();

    await _showSettings(tester);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    // Sound, music, haptics.
    expect(switches, hasLength(3));
    expect(switches[0].value, isFalse);
    expect(switches[1].value, isFalse);
    expect(switches[2].value, isTrue);
  });

  testWidgets('toggling a switch updates and persists the preference',
      (tester) async {
    await _showSettings(tester);
    expect(BmAudioSettings.soundEnabled, isTrue);

    await tester.tap(find.byType(Switch).first);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(BmAudioSettings.soundEnabled, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(BmAudioSettings.soundKey), isFalse);
  });

  testWidgets('haptics toggle stays independent of sound', (tester) async {
    await _showSettings(tester);

    await tester.tap(find.byType(Switch).last);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(BmAudioSettings.hapticsEnabled, isFalse);
    expect(BmAudioSettings.soundEnabled, isTrue);
  });

  testWidgets('music toggle saves and leaves the other switches alone',
      (tester) async {
    await _showSettings(tester);

    await tester.tap(find.byType(Switch).at(1));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(BmAudioSettings.musicEnabled, isFalse);
    expect(BmAudioSettings.soundEnabled, isTrue);
    expect(BmAudioSettings.hapticsEnabled, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(BmAudioSettings.musicKey), isFalse);
  });
}
