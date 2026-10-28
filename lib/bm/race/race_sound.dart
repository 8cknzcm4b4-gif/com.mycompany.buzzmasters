import 'package:flutter/services.dart';

import '../settings/bm_audio_settings.dart';

/// Sound and haptic cues for the race.
///
/// Uses platform system sounds, so the app needs no audio plugin and no
/// bundled clips. Sound follows the Sound Effects toggle and feedback follows
/// the Haptic Feedback toggle in settings; on platforms without either the
/// calls stay silent rather than fail.
class RaceSound {
  const RaceSound._();

  static Future<void> _click() async {
    if (!BmAudioSettings.soundEnabled) return;
    try {
      await SystemSound.play(SystemSoundType.click);
    } on Exception {
      // Platform has no system sound; the race continues silently.
    }
  }

  static Future<void> _alert() async {
    if (!BmAudioSettings.soundEnabled) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
    } on Exception {
      // Platform has no system sound; the race continues silently.
    }
  }

  static Future<void> _haptic(Future<void> Function() cue) async {
    if (!BmAudioSettings.hapticsEnabled) return;
    try {
      await cue();
    } on Exception {
      // No haptics on this device.
    }
  }

  /// The player locked in a correct answer.
  static Future<void> answerCorrect() async {
    await _click();
    await _haptic(HapticFeedback.lightImpact);
  }

  /// The player locked in a wrong answer.
  static Future<void> answerWrong() => _click();

  /// One second of the pre-race countdown elapsed.
  static Future<void> countdownTick() async {
    await _click();
    await _haptic(HapticFeedback.selectionClick);
  }

  /// The countdown reached zero and the race is on.
  static Future<void> go() async {
    await _alert();
    await _haptic(HapticFeedback.lightImpact);
  }

  /// A racer crossed the line and the race is over.
  static Future<void> finish() async {
    await _click();
    await _haptic(HapticFeedback.mediumImpact);
  }

  /// A racer failed to escape the danger zone and is out.
  static Future<void> eliminated() async {
    await _alert();
    await _haptic(HapticFeedback.heavyImpact);
  }
}
