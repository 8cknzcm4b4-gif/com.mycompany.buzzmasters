import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../settings/bm_audio_settings.dart';

/// Sound and haptic cues for the race.
///
/// Plays the bundled Buzz Masters cues in `assets/audios/sfx/` (original,
/// synthesised for the game). Sound follows the Sound Effects toggle and
/// feedback follows the Haptic Feedback toggle in settings; if a platform
/// cannot play audio the call falls back to a system click, and failing that
/// stays silent rather than interrupting the race.
class RaceSound {
  const RaceSound._();

  static final Map<String, AudioPlayer> _players = {};

  /// Audio plugins are absent under `flutter test`, whose binding is not a
  /// [WidgetsFlutterBinding]; cues stay silent there.
  static bool get _canPlay => WidgetsBinding.instance is WidgetsFlutterBinding;

  static Future<void> _play(String cue, {double volume = 0.8}) async {
    if (!BmAudioSettings.soundEnabled || !_canPlay) return;
    try {
      var player = _players[cue];
      if (player == null) {
        player = AudioPlayer(playerId: 'bm_$cue');
        _players[cue] = player;
        await player.setReleaseMode(ReleaseMode.stop);
      }
      await player.stop();
      await player.play(
        AssetSource('audios/sfx/$cue.wav'),
        volume: volume,
        mode: PlayerMode.lowLatency,
      );
    } on Object {
      try {
        await SystemSound.play(SystemSoundType.click);
      } on Object {
        // Platform has no sound at all; the race continues silently.
      }
    }
  }

  static Future<void> _haptic(Future<void> Function() cue) async {
    if (!BmAudioSettings.hapticsEnabled) return;
    try {
      await cue();
    } on Object {
      // No haptics on this device.
    }
  }

  /// The player locked in a correct answer.
  static Future<void> answerCorrect() async {
    await _play('correct');
    await _haptic(HapticFeedback.lightImpact);
  }

  /// The player locked in a wrong answer.
  static Future<void> answerWrong() async {
    await _play('wrong', volume: 0.6);
    await _haptic(HapticFeedback.heavyImpact);
  }

  /// One second of the pre-race countdown elapsed.
  static Future<void> countdownTick() async {
    await _play('countdown');
    await _haptic(HapticFeedback.selectionClick);
  }

  /// The countdown reached zero and the race is on.
  static Future<void> go() async {
    await _play('go');
    await _haptic(HapticFeedback.mediumImpact);
  }

  /// The player moved up a place.
  static Future<void> overtake() async {
    await _play('overtake', volume: 0.55);
    await _haptic(HapticFeedback.lightImpact);
  }

  /// A racer crossed the line and the race is over.
  static Future<void> finish() async {
    await _play('finish');
    await _haptic(HapticFeedback.mediumImpact);
  }

  /// A racer failed to escape the danger zone and is out.
  static Future<void> eliminated() async {
    await _play('eliminated', volume: 0.6);
    await _haptic(HapticFeedback.heavyImpact);
  }
}
