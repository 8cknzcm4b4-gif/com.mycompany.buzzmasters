import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzz_masters/bm/race/race_sound.dart';
import 'package:buzz_masters/bm/settings/bm_audio_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BmAudioSettings.resetForTests();
  });

  test('sound and haptics default to on', () async {
    await BmAudioSettings.ensureLoaded();
    expect(BmAudioSettings.soundEnabled, isTrue);
    expect(BmAudioSettings.hapticsEnabled, isTrue);
  });

  test('saved preferences are loaded', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      BmAudioSettings.soundKey: false,
      BmAudioSettings.hapticsKey: false,
    });
    BmAudioSettings.resetForTests();

    await BmAudioSettings.ensureLoaded();

    expect(BmAudioSettings.soundEnabled, isFalse);
    expect(BmAudioSettings.hapticsEnabled, isFalse);
  });

  test('toggles update and persist', () async {
    await BmAudioSettings.ensureLoaded();

    await BmAudioSettings.setSoundEnabled(false);
    await BmAudioSettings.setHapticsEnabled(false);

    expect(BmAudioSettings.soundEnabled, isFalse);
    expect(BmAudioSettings.hapticsEnabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(BmAudioSettings.soundKey), isFalse);
    expect(prefs.getBool(BmAudioSettings.hapticsKey), isFalse);
  });

  testWidgets('race cues stay silent when both toggles are off', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await BmAudioSettings.setSoundEnabled(false);
    await BmAudioSettings.setHapticsEnabled(false);

    await RaceSound.countdownTick();
    await RaceSound.go();
    await RaceSound.finish();
    await RaceSound.eliminated();
    await RaceSound.answerCorrect();

    expect(calls, isEmpty);
  });

  testWidgets('race cues fire when the toggles are on', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await BmAudioSettings.setSoundEnabled(true);
    await BmAudioSettings.setHapticsEnabled(true);

    await RaceSound.countdownTick();

    expect(calls, isNotEmpty);
  });

  testWidgets('sound off keeps haptics working', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await BmAudioSettings.setSoundEnabled(false);
    await BmAudioSettings.setHapticsEnabled(true);

    await RaceSound.countdownTick();

    expect(calls, isNot(contains('SystemSound.play')));
    expect(calls, contains('HapticFeedback.vibrate'));
  });
}
