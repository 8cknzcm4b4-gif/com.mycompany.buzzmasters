import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Six-digit race codes, e.g. `482913`.
abstract final class RaceCode {
  static final _pattern = RegExp(r'^\d{6}$');

  /// Strips spaces and dashes so `482-913` and `482 913` are accepted.
  static String normalise(String input) =>
      input.replaceAll(RegExp(r'[\s-]'), '');

  /// Null when valid, otherwise a message for the player.
  static String? validate(String input) {
    final code = normalise(input);
    if (code.isEmpty) return 'Enter the 6-digit race code from the host.';
    if (RegExp(r'\D').hasMatch(code)) return 'Race codes contain digits only.';
    if (!_pattern.hasMatch(code)) return 'Race codes are exactly 6 digits.';
    return null;
  }
}

/// Why a code lookup did not produce a joinable lobby.
enum JoinFailure {
  notFound,
  expired,
  full,
  alreadyStarted,
  offline,
  notConfigured
}

extension JoinFailureMessage on JoinFailure {
  String get message => switch (this) {
        JoinFailure.notFound => 'No race exists with that code.',
        JoinFailure.expired =>
          'That race has expired. Ask the host for a new code.',
        JoinFailure.full => 'That race is full — all six seats are taken.',
        JoinFailure.alreadyStarted => 'That race has already started.',
        JoinFailure.offline =>
          'Could not reach the Buzz Masters server. Check your connection and try again.',
        JoinFailure.notConfigured =>
          'Online races are not available in this build: no Buzz Masters game '
              'server is connected yet. Practice Race and Time Trial work offline.',
      };
}

/// A lobby the player has joined.
@immutable
class LobbySession {
  const LobbySession({
    required this.code,
    required this.lobbyId,
    required this.hostName,
    required this.players,
    required this.joinedAt,
  });

  final String code;
  final String lobbyId;
  final String hostName;
  final List<String> players;
  final DateTime joinedAt;

  Map<String, Object> toJson() => {
        'code': code,
        'lobbyId': lobbyId,
        'hostName': hostName,
        'players': players,
        'joinedAt': joinedAt.toIso8601String(),
      };

  static LobbySession? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = json['code'];
    final id = json['lobbyId'];
    final at = DateTime.tryParse('${json['joinedAt']}');
    if (code is! String || id is! String || at == null) return null;
    return LobbySession(
      code: code,
      lobbyId: id,
      hostName: '${json['hostName'] ?? ''}',
      players: [for (final p in (json['players'] as List?) ?? const []) '$p'],
      joinedAt: at,
    );
  }
}

/// Result of [OnlineRaceService.join] or [OnlineRaceService.resume].
@immutable
class JoinResult {
  const JoinResult.joined(LobbySession this.session) : failure = null;
  const JoinResult.failed(JoinFailure this.failure) : session = null;

  final LobbySession? session;
  final JoinFailure? failure;

  bool get ok => session != null;
}

/// The online lobby boundary. The real implementation must check every code
/// with the server; nothing here may invent a lobby or a room number.
abstract class OnlineRaceService {
  bool get isConfigured;

  Future<JoinResult> join(String code);

  /// Re-validates a previously joined lobby with the server.
  Future<JoinResult> resume(LobbySession previous);
}

/// The build has no Buzz Masters game server, so every online call reports
/// exactly that.
class UnconfiguredOnlineRaceService implements OnlineRaceService {
  const UnconfiguredOnlineRaceService();

  @override
  bool get isConfigured => false;

  @override
  Future<JoinResult> join(String code) async =>
      const JoinResult.failed(JoinFailure.notConfigured);

  @override
  Future<JoinResult> resume(LobbySession previous) async =>
      const JoinResult.failed(JoinFailure.notConfigured);
}

/// Process-wide service and the last genuinely joined lobby.
abstract final class OnlineRace {
  static OnlineRaceService service = const UnconfiguredOnlineRaceService();

  static const _lastKey = 'bm_last_online_session_v1';

  /// Sessions older than this are not offered for resume.
  static const resumeWindow = Duration(hours: 2);

  /// Only ever written after the server confirmed a join.
  static Future<void> remember(LobbySession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastKey, jsonEncode(session.toJson()));
    } on Object {
      // Not remembering a session only hides the resume card.
    }
  }

  static Future<void> forget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastKey);
    } on Object {
      // Nothing stored.
    }
  }

  /// The last joined lobby if it is recent enough to try resuming, else null.
  static Future<LobbySession?> lastResumable({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastKey);
      if (raw == null) return null;
      final session = LobbySession.fromJson(jsonDecode(raw));
      if (session == null) return null;
      final age = (now ?? DateTime.now()).difference(session.joinedAt);
      return age <= resumeWindow ? session : null;
    } on Object {
      return null;
    }
  }
}
