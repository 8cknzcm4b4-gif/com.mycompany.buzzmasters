import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'time_trial.dart';

/// Where the player's best time trial ghost is kept.
abstract class TimeTrialStore {
  Future<GhostTrack?> loadBest();
  Future<void> saveBest(GhostTrack track);
}

/// Stores the best ghost in shared preferences, under one key per distance so
/// a short and a long race do not overwrite each other.
class PrefsTimeTrialStore implements TimeTrialStore {
  const PrefsTimeTrialStore();

  static String keyFor(int distance) => 'bm_time_trial_best_$distance';

  @override
  Future<GhostTrack?> loadBest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith('bm_time_trial_best_')) continue;
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          return GhostTrack.fromJson(decoded);
        }
      }
    } on Exception {
      // Unreadable or corrupt save: start without a ghost.
    }
    return null;
  }

  @override
  Future<void> saveBest(GhostTrack track) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        keyFor(track.distance),
        jsonEncode(track.toJson()),
      );
    } on Exception {
      // Best effort: a failed save only costs the ghost next time.
    }
  }
}

/// In-memory store for tests and session-only play.
class MemoryTimeTrialStore implements TimeTrialStore {
  MemoryTimeTrialStore([this.best]);

  GhostTrack? best;
  int saveCount = 0;

  @override
  Future<GhostTrack?> loadBest() async => best;

  @override
  Future<void> saveBest(GhostTrack track) async {
    best = track;
    saveCount++;
  }
}
