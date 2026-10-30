import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/bm_theme.dart';

/// The player's on-device identity and race record.
///
/// There is no Buzz Masters account backend yet, so this lives in shared
/// preferences. Every number shown on the dashboard, profile and leaderboard
/// comes from here; nothing is invented.
@immutable
class PlayerStats {
  const PlayerStats({
    this.name = 'Player',
    this.colorIndex = 1,
    this.races = 0,
    this.wins = 0,
    this.podiums = 0,
    this.correct = 0,
    this.answered = 0,
    this.bestPlacing = 0,
    this.winStreak = 0,
    this.bestWinStreak = 0,
    this.recent = const [],
  });

  final String name;
  final int colorIndex;
  final int races;
  final int wins;
  final int podiums;
  final int correct;
  final int answered;

  /// Best finishing place so far, 0 when the player has not raced.
  final int bestPlacing;
  final int winStreak;
  final int bestWinStreak;

  /// Most recent race placings, newest first (max 10).
  final List<int> recent;

  Color get color =>
      BmColors.seatColors[colorIndex % BmColors.seatColors.length];

  String get initial =>
      name.isEmpty ? '?' : name.characters.first.toUpperCase();

  int get accuracy => answered == 0 ? 0 : (correct * 100 / answered).round();

  int get xp => correct * 10 + races * 25 + podiums * 40 + wins * 100;

  /// Level 1 starts at 0 XP; each level needs a little more than the last.
  int get level => 1 + math.sqrt(xp / 120).floor();

  int _xpFor(int lvl) => ((lvl - 1) * (lvl - 1) * 120);

  /// 0..1 progress through the current level.
  double get levelProgress {
    final start = _xpFor(level);
    final end = _xpFor(level + 1);
    return ((xp - start) / (end - start)).clamp(0.0, 1.0);
  }

  int get xpToNext => _xpFor(level + 1) - xp;

  PlayerStats copyWith({
    String? name,
    int? colorIndex,
    int? races,
    int? wins,
    int? podiums,
    int? correct,
    int? answered,
    int? bestPlacing,
    int? winStreak,
    int? bestWinStreak,
    List<int>? recent,
  }) =>
      PlayerStats(
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        races: races ?? this.races,
        wins: wins ?? this.wins,
        podiums: podiums ?? this.podiums,
        correct: correct ?? this.correct,
        answered: answered ?? this.answered,
        bestPlacing: bestPlacing ?? this.bestPlacing,
        winStreak: winStreak ?? this.winStreak,
        bestWinStreak: bestWinStreak ?? this.bestWinStreak,
        recent: recent ?? this.recent,
      );

  /// Folds one finished race into the record.
  PlayerStats withRace({
    required int placing,
    required int correctAnswers,
    required int answeredQuestions,
  }) {
    final won = placing == 1;
    final streak = won ? winStreak + 1 : 0;
    return copyWith(
      races: races + 1,
      wins: wins + (won ? 1 : 0),
      podiums: podiums + (placing <= 3 ? 1 : 0),
      correct: correct + correctAnswers,
      answered: answered + answeredQuestions,
      bestPlacing: bestPlacing == 0 ? placing : math.min(bestPlacing, placing),
      winStreak: streak,
      bestWinStreak: math.max(bestWinStreak, streak),
      recent: [placing, ...recent].take(10).toList(),
    );
  }

  Map<String, Object> toJson() => {
        'name': name,
        'colorIndex': colorIndex,
        'races': races,
        'wins': wins,
        'podiums': podiums,
        'correct': correct,
        'answered': answered,
        'bestPlacing': bestPlacing,
        'winStreak': winStreak,
        'bestWinStreak': bestWinStreak,
        'recent': recent,
      };

  static PlayerStats fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    final rawName = (json['name'] as String?)?.trim() ?? '';
    return PlayerStats(
      name: rawName.isEmpty ? 'Player' : rawName,
      colorIndex: n('colorIndex'),
      races: n('races'),
      wins: n('wins'),
      podiums: n('podiums'),
      correct: n('correct'),
      answered: n('answered'),
      bestPlacing: n('bestPlacing'),
      winStreak: n('winStreak'),
      bestWinStreak: n('bestWinStreak'),
      recent: [
        for (final v in (json['recent'] as List?) ?? const [])
          if (v is num) v.toInt(),
      ],
    );
  }
}

/// An achievement and whether these stats have unlocked it.
class Achievement {
  const Achievement(this.title, this.detail, this.icon, this.unlocked,
      {this.progress = 0});

  final String title;
  final String detail;
  final IconData icon;
  final bool unlocked;

  /// 0..1 towards unlocking.
  final double progress;

  static List<Achievement> forStats(PlayerStats s) {
    double p(int have, int need) => (have / need).clamp(0.0, 1.0);
    return [
      Achievement('First Lap', 'Finish your first race', Icons.flag_rounded,
          s.races >= 1,
          progress: p(s.races, 1)),
      Achievement('Podium Finisher', 'Finish in the top three',
          Icons.military_tech_rounded, s.podiums >= 1,
          progress: p(s.podiums, 1)),
      Achievement(
          'Champion', 'Win a race', Icons.emoji_events_rounded, s.wins >= 1,
          progress: p(s.wins, 1)),
      Achievement('Hat-Trick', 'Win three races in a row',
          Icons.local_fire_department_rounded, s.bestWinStreak >= 3,
          progress: p(s.bestWinStreak, 3)),
      Achievement('Quiz Engine', 'Answer 50 questions correctly',
          Icons.bolt_rounded, s.correct >= 50,
          progress: p(s.correct, 50)),
      Achievement(
          'Marathon', 'Complete 25 races', Icons.speed_rounded, s.races >= 25,
          progress: p(s.races, 25)),
    ];
  }
}

abstract final class PlayerProfileStore {
  static const _key = 'bm_player_profile_v1';

  static final ValueNotifier<PlayerStats> current =
      ValueNotifier(const PlayerStats());

  static Future<void>? _loading;

  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        current.value = PlayerStats.fromJson(decoded);
      }
    } on Object {
      // Missing or corrupt save: start from a fresh profile.
    }
  }

  static Future<void> update(PlayerStats Function(PlayerStats) change) async {
    await ensureLoaded();
    current.value = change(current.value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(current.value.toJson()));
    } on Object {
      // Keep the in-memory record even when the store rejects the write.
    }
  }

  static Future<void> setName(String name) {
    final clean = name.trim();
    final capped = clean.length > 16 ? clean.substring(0, 16) : clean;
    return update((s) => s.copyWith(name: capped.isEmpty ? 'Player' : capped));
  }

  static Future<void> setColor(int index) =>
      update((s) => s.copyWith(colorIndex: index));

  static Future<void> recordRace({
    required int placing,
    required int correctAnswers,
    required int answeredQuestions,
  }) =>
      update((s) => s.withRace(
            placing: placing,
            correctAnswers: correctAnswers,
            answeredQuestions: answeredQuestions,
          ));

  @visibleForTesting
  static void resetForTests() {
    _loading = null;
    current.value = const PlayerStats();
  }
}
