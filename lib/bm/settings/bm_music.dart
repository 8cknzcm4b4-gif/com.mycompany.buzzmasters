import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import 'bm_audio_settings.dart';

/// Background arena music: one original looping track, following the Music
/// toggle in settings. Browsers block audio until the first tap, so a failed
/// start is retried the next time [start] is called.
abstract final class BmMusic {
  static AudioPlayer? _player;
  static bool _playing = false;
  static bool _listening = false;

  static bool get _canPlay => WidgetsBinding.instance is WidgetsFlutterBinding;

  static Future<void> start() async {
    if (!_listening) {
      _listening = true;
      BmAudioSettings.music.addListener(() {
        unawaited(BmAudioSettings.musicEnabled ? start() : stop());
      });
    }
    if (!_canPlay || _playing || !BmAudioSettings.musicEnabled) return;
    try {
      var player = _player;
      if (player == null) {
        player = _player = AudioPlayer(playerId: 'bm_music');
        await player.setReleaseMode(ReleaseMode.loop);
      }
      await player.play(AssetSource('audios/sfx/arena_loop.wav'), volume: 0.35);
      _playing = true;
    } on Object {
      _playing = false;
    }
  }

  static Future<void> stop() async {
    _playing = false;
    try {
      await _player?.stop();
    } on Object {
      // Nothing playing.
    }
  }
}
