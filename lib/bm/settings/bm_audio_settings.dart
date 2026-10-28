import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Player audio preferences, shared by the settings screen and the race cues.
///
/// The values live in [ValueNotifier]s so the switches and the race cues stay
/// in step, and are written to shared preferences on every change.
class BmAudioSettings {
  const BmAudioSettings._();

  static const soundKey = 'bm_sound_effects';
  static const hapticsKey = 'bm_haptic_feedback';

  static final ValueNotifier<bool> soundEffects = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> haptics = ValueNotifier<bool>(true);

  static bool get soundEnabled => soundEffects.value;
  static bool get hapticsEnabled => haptics.value;

  static Future<void>? _loading;
  static bool _touched = false;

  /// Loads saved preferences once; later calls reuse the in-flight future.
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // A toggle flipped before the read finished wins over the saved value.
      if (_touched) return;
      soundEffects.value = prefs.getBool(soundKey) ?? true;
      haptics.value = prefs.getBool(hapticsKey) ?? true;
    } on Exception {
      // Preferences unavailable: keep the defaults.
    }
  }

  static Future<void> setSoundEnabled(bool value) async {
    _touched = true;
    soundEffects.value = value;
    await _write(soundKey, value);
  }

  static Future<void> setHapticsEnabled(bool value) async {
    _touched = true;
    haptics.value = value;
    await _write(hapticsKey, value);
  }

  static Future<void> _write(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } on Exception {
      // Keep the in-memory value even when the store rejects the write.
    }
  }

  /// Clears cached state so tests start from a known point.
  @visibleForTesting
  static void resetForTests() {
    _loading = null;
    _touched = false;
    soundEffects.value = true;
    haptics.value = true;
  }
}
