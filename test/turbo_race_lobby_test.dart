import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzz_masters/bm/race/turbo_race_lobby_screen.dart';
import 'package:buzz_masters/bm/screens/settings_screen.dart';
import 'package:buzz_masters/bm/settings/bm_audio_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BmAudioSettings.resetForTests();
  });

  testWidgets('the race lobby opens settings for sound and haptics',
      (tester) async {
    // The test font is wider than Poppins, so give the lobby's long button
    // labels room to sit on one line.
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: TurboRaceLobbyScreen()));
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byType(BmSettingsScreen), findsNothing);

    await tester.tap(find.byIcon(Icons.settings_rounded));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.byType(BmSettingsScreen), findsOneWidget);
    expect(find.text('SOUND EFFECTS'), findsOneWidget);
    expect(find.text('HAPTIC FEEDBACK'), findsOneWidget);
  });
}
