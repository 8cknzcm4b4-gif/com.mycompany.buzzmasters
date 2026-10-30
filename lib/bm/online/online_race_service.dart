import 'package:flutter/foundation.dart';

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

/// Error codes returned by the Buzz Masters server (see
/// supabase/migrations/20261030000100_multiplayer.sql) plus client-side ones.
abstract final class OnlineError {
  static const notConfigured = 'not_configured';
  static const offline = 'offline';
  static const signInFailed = 'sign_in_failed';

  static String message(String code) => switch (code) {
        'not_found' => 'No race exists with that code.',
        'expired' => 'That race has expired. Ask the host for a new code.',
        'full' => 'That race is full — all six seats are taken.',
        'already_started' => 'That race has already started.',
        'invalid_code' => 'Race codes are exactly 6 digits.',
        'not_member' => 'You are no longer in that race.',
        'not_host' => 'Only the host can do that.',
        'not_enough_players' => 'At least 2 racers are needed to start.',
        'none' => 'You have no race to resume.',
        'self' => 'That is your own friend code.',
        'already_friends' => 'You are already friends.',
        'not_friends' => 'You can only invite friends.',
        'duplicate' => 'You already answered this question.',
        'too_late' => 'Too late — the question closed.',
        signInFailed =>
          'Could not start an online session. Anonymous sign-ins may be '
              'disabled for this Buzz Masters project.',
        offline =>
          'Could not reach the Buzz Masters server. Check your connection '
              'and try again.',
        notConfigured =>
          'Online races are not available in this build: no Buzz Masters game '
              'server is connected yet. Practice Race and Time Trial work offline.',
        _ => 'Something went wrong ($code). Please try again.',
      };
}

/// A value or a server error code.
@immutable
class OnlineResult<T> {
  const OnlineResult.ok(T this.value) : error = null;
  const OnlineResult.fail(String this.error) : value = null;

  final T? value;
  final String? error;

  bool get ok => error == null;
  String get message => OnlineError.message(error ?? '');
}

enum RoomStatus { lobby, countdown, racing, finished, abandoned }

int _int(Object? v, [int fallback = 0]) => v is num
    ? v.toInt()
    : (v is String ? int.tryParse(v) ?? fallback : fallback);
int? _intOrNull(Object? v) => v == null ? null : _int(v);

@immutable
class RoomPlayer {
  const RoomPlayer({
    required this.id,
    required this.seat,
    required this.name,
    required this.color,
    this.progress = 0,
    this.speed = 'stopped',
    this.finished = false,
    this.finishedMs,
    this.eliminated = false,
    this.danger = false,
    this.connected = true,
    this.left = false,
    this.isMe = false,
    this.isHost = false,
  });

  factory RoomPlayer.fromJson(Map<String, dynamic> j) => RoomPlayer(
        id: '${j['id']}',
        seat: _int(j['seat'], 1),
        name: '${j['name'] ?? 'Racer'}',
        color: _int(j['color'], 1),
        progress: _int(j['progress']),
        speed: '${j['speed'] ?? 'stopped'}',
        finished: j['finished'] == true,
        finishedMs: _intOrNull(j['finished_ms']),
        eliminated: j['eliminated'] == true,
        danger: j['danger'] == true,
        connected: j['connected'] != false,
        left: j['left'] == true,
        isMe: j['is_me'] == true,
        isHost: j['is_host'] == true,
      );

  final String id;
  final int seat;
  final String name;
  final int color;
  final int progress;
  final String speed;
  final bool finished;
  final int? finishedMs;
  final bool eliminated;
  final bool danger;
  final bool connected;
  final bool left;
  final bool isMe;
  final bool isHost;
}

@immutable
class RoomQuestion {
  const RoomQuestion({
    required this.index,
    required this.prompt,
    required this.options,
    this.category = '',
    this.difficulty = '',
    required this.remainingMs,
  });

  factory RoomQuestion.fromJson(Map<String, dynamic> j) => RoomQuestion(
        index: _int(j['index']),
        prompt: '${j['prompt'] ?? ''}',
        options: [for (final o in (j['options'] as List?) ?? const []) '$o'],
        category: '${j['category'] ?? ''}',
        difficulty: '${j['difficulty'] ?? ''}',
        remainingMs: _int(j['remaining_ms']),
      );

  final int index;
  final String prompt;
  final List<String> options;
  final String category;
  final String difficulty;

  /// Window left when the server built this state.
  final int remainingMs;
}

@immutable
class RoomAnswer {
  const RoomAnswer({this.option, required this.correct, required this.delta});

  factory RoomAnswer.fromJson(Map<String, dynamic> j) => RoomAnswer(
        option: _intOrNull(j['option']),
        correct: j['correct'] == true,
        delta: _int(j['delta']),
      );

  /// Null when the question timed out.
  final int? option;
  final bool correct;
  final int delta;
}

@immutable
class RoomResult {
  const RoomResult({
    required this.id,
    required this.placing,
    required this.name,
    required this.color,
    required this.progress,
    this.finished = false,
    this.eliminated = false,
    this.correct = 0,
    this.answered = 0,
    this.isMe = false,
  });

  factory RoomResult.fromJson(Map<String, dynamic> j) => RoomResult(
        id: '${j['id']}',
        placing: _int(j['placing'], 1),
        name: '${j['name'] ?? 'Racer'}',
        color: _int(j['color'], 1),
        progress: _int(j['progress']),
        finished: j['finished'] == true,
        eliminated: j['eliminated'] == true,
        correct: _int(j['correct']),
        answered: _int(j['answered']),
        isMe: j['is_me'] == true,
      );

  final String id;
  final int placing;
  final String name;
  final int color;
  final int progress;
  final bool finished;
  final bool eliminated;
  final int correct;
  final int answered;
  final bool isMe;
}

/// One snapshot of a room as the server sees it.
@immutable
class RoomState {
  const RoomState({
    required this.roomId,
    required this.code,
    required this.status,
    required this.players,
    this.isHost = false,
    this.countdownMs,
    this.questionNumber = 0,
    this.questionsResolved = 0,
    this.nextQuestionInMs,
    this.lastCorrectIndex,
    this.question,
    this.myAnswer,
    this.results,
    this.distance = 100,
    this.windowMs = 8000,
    this.maxQuestions = 30,
    this.maxSeats = 6,
    this.minPlayers = 2,
  });

  factory RoomState.fromJson(Map<String, dynamic> j) {
    final rules = (j['rules'] as Map?)?.cast<String, dynamic>() ?? const {};
    final q = j['question'];
    final mine = j['my_answer'];
    final results = j['results'];
    return RoomState(
      roomId: '${j['room_id']}',
      code: '${j['code']}',
      status: RoomStatus.values.firstWhere((s) => s.name == j['status'],
          orElse: () => RoomStatus.abandoned),
      isHost: j['is_host'] == true,
      countdownMs: _intOrNull(j['countdown_ms']),
      questionNumber: _int(j['question_number']),
      questionsResolved: _int(j['questions_resolved']),
      nextQuestionInMs: _intOrNull(j['next_question_in_ms']),
      lastCorrectIndex: _intOrNull(j['last_correct_index']),
      players: [
        for (final p in (j['players'] as List?) ?? const [])
          RoomPlayer.fromJson((p as Map).cast<String, dynamic>()),
      ],
      question:
          q is Map ? RoomQuestion.fromJson(q.cast<String, dynamic>()) : null,
      myAnswer: mine is Map
          ? RoomAnswer.fromJson(mine.cast<String, dynamic>())
          : null,
      results: results is List
          ? [
              for (final r in results)
                RoomResult.fromJson((r as Map).cast<String, dynamic>()),
            ]
          : null,
      distance: _int(rules['distance'], 100),
      windowMs: _int(rules['window_ms'], 8000),
      maxQuestions: _int(rules['max_questions'], 30),
      maxSeats: _int(rules['max_seats'], 6),
      minPlayers: _int(rules['min_players'], 2),
    );
  }

  final String roomId;
  final String code;
  final RoomStatus status;
  final List<RoomPlayer> players;
  final bool isHost;
  final int? countdownMs;
  final int questionNumber;
  final int questionsResolved;
  final int? nextQuestionInMs;
  final int? lastCorrectIndex;
  final RoomQuestion? question;
  final RoomAnswer? myAnswer;
  final List<RoomResult>? results;
  final int distance;
  final int windowMs;
  final int maxQuestions;
  final int maxSeats;
  final int minPlayers;

  RoomPlayer? get me {
    for (final p in players) {
      if (p.isMe) return p;
    }
    return null;
  }

  String get hostName {
    for (final p in players) {
      if (p.isHost) return p.name;
    }
    return '';
  }

  bool get isLive =>
      status == RoomStatus.lobby ||
      status == RoomStatus.countdown ||
      status == RoomStatus.racing;

  /// Race positions with the server's ranking rule: finishers by time, then
  /// racers still in by distance, then eliminated racers; seat breaks ties.
  Map<String, int> get positions {
    final order = [...players]..sort((a, b) {
        if (a.finished != b.finished) return a.finished ? -1 : 1;
        if (a.finished) {
          final t = (a.finishedMs ?? 0).compareTo(b.finishedMs ?? 0);
          if (t != 0) return t;
        } else if (a.eliminated != b.eliminated) {
          return a.eliminated ? 1 : -1;
        }
        final p = b.progress.compareTo(a.progress);
        return p != 0 ? p : a.seat.compareTo(b.seat);
      });
    return {for (var i = 0; i < order.length; i++) order[i].id: i + 1};
  }
}

@immutable
class AnswerOutcome {
  const AnswerOutcome({
    required this.correct,
    required this.delta,
    required this.progress,
  });

  final bool correct;
  final int delta;
  final int progress;
}

@immutable
class LeaderboardRow {
  const LeaderboardRow({
    required this.rank,
    required this.name,
    required this.color,
    required this.wins,
    required this.podiums,
    required this.races,
    this.isMe = false,
  });

  factory LeaderboardRow.fromJson(Map<String, dynamic> j) => LeaderboardRow(
        rank: _int(j['rank'], 1),
        name: '${j['name'] ?? 'Racer'}',
        color: _int(j['color'], 1),
        wins: _int(j['wins']),
        podiums: _int(j['podiums']),
        races: _int(j['races']),
        isMe: j['is_me'] == true,
      );

  final int rank;
  final String name;
  final int color;
  final int wins;
  final int podiums;
  final int races;
  final bool isMe;
}

@immutable
class FriendEntry {
  const FriendEntry({required this.id, required this.name, this.color = 1});

  factory FriendEntry.fromJson(Map<String, dynamic> j) => FriendEntry(
      id: '${j['id']}',
      name: '${j['name'] ?? 'Racer'}',
      color: _int(j['color'], 1));

  final String id;
  final String name;
  final int color;
}

@immutable
class RaceInvite {
  const RaceInvite(
      {required this.roomId, required this.code, required this.from});

  factory RaceInvite.fromJson(Map<String, dynamic> j) => RaceInvite(
      roomId: '${j['room_id']}',
      code: '${j['code']}',
      from: '${j['from'] ?? ''}');

  final String roomId;
  final String code;
  final String from;
}

@immutable
class FriendsSnapshot {
  const FriendsSnapshot({
    required this.myCode,
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.invites = const [],
  });

  factory FriendsSnapshot.fromJson(Map<String, dynamic> j) {
    List<FriendEntry> list(String key) => [
          for (final f in (j[key] as List?) ?? const [])
            FriendEntry.fromJson((f as Map).cast<String, dynamic>()),
        ];
    return FriendsSnapshot(
      myCode: '${j['my_code'] ?? ''}',
      friends: list('friends'),
      incoming: list('incoming'),
      outgoing: list('outgoing'),
      invites: [
        for (final i in (j['invites'] as List?) ?? const [])
          RaceInvite.fromJson((i as Map).cast<String, dynamic>()),
      ],
    );
  }

  final String myCode;
  final List<FriendEntry> friends;
  final List<FriendEntry> incoming;
  final List<FriendEntry> outgoing;
  final List<RaceInvite> invites;
}

/// The online game API. The real implementation is
/// [SupabaseOnlineRaceService]; every rule is enforced by the server, so
/// nothing here may decide a lobby exists, an answer is right or who won.
abstract class OnlineRaceService {
  bool get isConfigured;

  Future<OnlineResult<RoomState>> createRoom();
  Future<OnlineResult<RoomState>> join(String code);
  Future<OnlineResult<RoomState>> roomState(String roomId);

  /// The player's live room according to the server, for "Resume".
  Future<OnlineResult<RoomState>> liveRoom();
  Future<OnlineResult<RoomState>> startRace(String roomId);
  Future<OnlineResult<AnswerOutcome>> submitAnswer(
      String roomId, int question, int option);
  Future<OnlineResult<bool>> leave(String roomId);

  Future<OnlineResult<List<LeaderboardRow>>> leaderboard();
  Future<OnlineResult<FriendsSnapshot>> friends();
  Future<OnlineResult<String>> sendFriendRequest(String code);
  Future<OnlineResult<bool>> respondToFriend(String friendId, bool accept);
  Future<OnlineResult<bool>> removeFriend(String friendId);
  Future<OnlineResult<bool>> inviteFriend(String roomId, String friendId);
}

/// The build has no Buzz Masters game server, so every online call reports
/// exactly that.
class UnconfiguredOnlineRaceService implements OnlineRaceService {
  const UnconfiguredOnlineRaceService();

  static const _no = OnlineError.notConfigured;

  @override
  bool get isConfigured => false;
  @override
  Future<OnlineResult<RoomState>> createRoom() async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<RoomState>> join(String code) async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<RoomState>> roomState(String roomId) async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<RoomState>> liveRoom() async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<RoomState>> startRace(String roomId) async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<AnswerOutcome>> submitAnswer(
          String roomId, int question, int option) async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<bool>> leave(String roomId) async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<List<LeaderboardRow>>> leaderboard() async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<FriendsSnapshot>> friends() async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<String>> sendFriendRequest(String code) async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<bool>> respondToFriend(
          String friendId, bool accept) async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<bool>> removeFriend(String friendId) async =>
      const OnlineResult.fail(_no);
  @override
  Future<OnlineResult<bool>> inviteFriend(
          String roomId, String friendId) async =>
      const OnlineResult.fail(_no);
}

/// Process-wide online service, swapped for the Supabase one at start-up
/// when the build is configured, and for fakes in tests.
abstract final class OnlineRace {
  static OnlineRaceService service = const UnconfiguredOnlineRaceService();
}
