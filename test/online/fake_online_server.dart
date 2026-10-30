import 'dart:math';

import 'package:buzz_masters/bm/game/practice_match.dart';
import 'package:buzz_masters/bm/online/online_race_service.dart';
import 'package:buzz_masters/bm/race/race_model.dart';

/// In-memory stand-in for the Buzz Masters server, following the same rules
/// as supabase/migrations/20261030000100_multiplayer.sql (which is tested on
/// real Postgres in supabase/tests). It returns the same JSON shape, so the
/// client's parsing is exercised too. Time only moves when a test says so.
class FakeOnlineServer {
  FakeOnlineServer({int seed = 1}) : _rng = Random(seed);

  static const cfg = kTurboRaceConfig;
  static const revealMs = 1500;
  static const countdownMs = 3000;

  final Random _rng;
  int now = 0;
  final rooms = <String, _Room>{};
  final _names = <String, String>{};
  final _colors = <String, int>{};
  final _friendCodes = <String, String>{};
  final _links = <String, String>{}; // 'req>addr' -> status
  final _invites = <String, Set<String>>{}; // roomId -> invitees
  final _results = <String, List<Map<String, Object?>>>{};
  int _seq = 0;

  /// A client signed in as [id], racing as [name].
  FakeOnlineClient client(String id, String name, {int color = 1}) {
    _names[id] = name;
    _colors[id] = color;
    _friendCodes.putIfAbsent(
        id, () => 'F${id.toUpperCase().padRight(5, 'X').substring(0, 5)}');
    return FakeOnlineClient(this, id);
  }

  void advance(int ms) => now += ms;

  int correctIndexFor(String roomId) {
    final r = rooms[roomId]!;
    return kPracticeQuestions[r.questionOrder[r.currentQ]].correctIndex;
  }

  _Room? _live(String code) {
    for (final r in rooms.values) {
      if (r.code == code && r.isLive) return r;
    }
    return null;
  }

  void _tick(_Room r) {
    for (var guard = 0; guard < 4; guard++) {
      if (r.status == 'lobby') {
        if (now >= r.expiresAt) r.status = 'abandoned';
        return;
      }
      if (r.status == 'countdown') {
        if (now < r.startsAt) return;
        r
          ..status = 'racing'
          ..currentQ = 0
          ..qOpenedAt = r.startsAt
          ..qResolved = false;
        continue;
      }
      if (r.status != 'racing') return;
      if (r.players.values.every((p) => p.left)) {
        r.status = 'abandoned';
        return;
      }
      if (now < r.qOpenedAt) return;
      final active = r.players.entries
          .where((e) => e.value.finishedMs == null && !e.value.eliminated);
      final unanswered =
          active.where((e) => !r.answers.containsKey('${e.key}#${r.currentQ}'));
      if (now < r.qOpenedAt + cfg.questionWindowMs && unanswered.isNotEmpty) {
        return;
      }
      for (final e in unanswered.toList()) {
        r.answers['${e.key}#${r.currentQ}'] = -1;
        e.value
          ..progress = max(0, e.value.progress - cfg.timeoutPenalty)
          ..speed = 'stopped';
      }
      if (r.resolved >= cfg.dangerFreeQuestions) {
        for (final p in r.players.values) {
          if (p.finishedMs != null || p.eliminated) continue;
          if (p.progress <= cfg.dangerZoneMax) {
            p.streak++;
            p.eliminated = p.streak > cfg.dangerGraceQuestions;
          } else {
            p.streak = 0;
          }
        }
      }
      r.lastCorrect =
          kPracticeQuestions[r.questionOrder[r.currentQ]].correctIndex;
      r.resolved++;
      final done = r.players.values.any((p) => p.finishedMs != null) ||
          r.players.values.every((p) => p.finishedMs != null || p.eliminated) ||
          r.resolved >= min(cfg.maxQuestions, r.questionOrder.length);
      if (done) {
        r
          ..status = 'finished'
          ..qResolved = true;
        _record(r);
        return;
      }
      r
        ..currentQ += 1
        ..qOpenedAt = now + revealMs
        ..qResolved = false;
    }
  }

  List<MapEntry<String, _Player>> _ranked(_Room r) => r.players.entries.toList()
    ..sort((a, b) {
      final x = a.value, y = b.value;
      if ((x.finishedMs == null) != (y.finishedMs == null)) {
        return x.finishedMs == null ? 1 : -1;
      }
      if (x.finishedMs != null && x.finishedMs != y.finishedMs) {
        return x.finishedMs!.compareTo(y.finishedMs!);
      }
      if (x.eliminated != y.eliminated) return x.eliminated ? 1 : -1;
      final p = y.progress.compareTo(x.progress);
      return p != 0 ? p : x.seat.compareTo(y.seat);
    });

  void _record(_Room r) {
    final ranked = _ranked(r);
    _results[r.id] = [
      for (var i = 0; i < ranked.length; i++)
        {
          'id': ranked[i].key,
          'placing': i + 1,
          'name': _names[ranked[i].key],
          'color': _colors[ranked[i].key],
          'progress': ranked[i].value.progress,
          'finished': ranked[i].value.finishedMs != null,
          'eliminated': ranked[i].value.eliminated,
          'correct': ranked[i].value.correct,
          'answered': ranked[i].value.answered,
        },
    ];
  }

  Map<String, Object?> _json(_Room r, String me) {
    final q = r.status == 'racing' && now >= r.qOpenedAt
        ? kPracticeQuestions[r.questionOrder[r.currentQ]]
        : null;
    final mine = r.answers['$me#${r.currentQ}'];
    return {
      'ok': true,
      'room_id': r.id,
      'code': r.code,
      'status': r.status,
      'is_host': r.host == me,
      'countdown_ms': r.status == 'countdown' ? max(0, r.startsAt - now) : null,
      'question_number': r.currentQ + 1,
      'questions_resolved': r.resolved,
      'next_question_in_ms':
          r.status == 'racing' && now < r.qOpenedAt ? r.qOpenedAt - now : null,
      'last_correct_index': r.lastCorrect,
      'rules': {
        'distance': cfg.distance,
        'window_ms': cfg.questionWindowMs,
        'max_questions': cfg.maxQuestions,
        'max_seats': 6,
        'min_players': 2,
      },
      'players': [
        for (final e
            in r.players.entries.toList()
              ..sort((a, b) => a.value.seat.compareTo(b.value.seat)))
          {
            'id': e.key,
            'seat': e.value.seat,
            'name': _names[e.key],
            'color': _colors[e.key],
            'progress': e.value.progress,
            'speed': e.value.speed,
            'finished': e.value.finishedMs != null,
            'finished_ms': e.value.finishedMs,
            'eliminated': e.value.eliminated,
            'danger': e.value.finishedMs == null &&
                !e.value.eliminated &&
                r.resolved >= cfg.dangerFreeQuestions &&
                e.value.progress <= cfg.dangerZoneMax,
            'connected': !e.value.left,
            'left': e.value.left,
            'is_me': e.key == me,
            'is_host': e.key == r.host,
          },
      ],
      'question': q == null
          ? null
          : {
              'index': r.currentQ,
              'category': q.category,
              'difficulty': q.difficulty,
              'prompt': q.text,
              'options': q.options,
              'remaining_ms':
                  max(0, cfg.questionWindowMs - (now - r.qOpenedAt)),
            },
      'my_answer': mine == null || r.status != 'racing'
          ? null
          : {
              'option': mine < 0 ? null : mine,
              'correct': mine >= 0 &&
                  mine ==
                      kPracticeQuestions[r.questionOrder[r.currentQ]]
                          .correctIndex,
              'delta': r.deltas['$me#${r.currentQ}'] ?? 0,
            },
      'results': r.status == 'finished'
          ? [
              for (final row in _results[r.id]!)
                {...row, 'is_me': row['id'] == me},
            ]
          : null,
    };
  }
}

class _Player {
  _Player(this.seat);
  final int seat;
  int progress = 0;
  int? finishedMs;
  bool eliminated = false;
  int streak = 0;
  String speed = 'stopped';
  int correct = 0;
  int answered = 0;
  bool left = false;
}

class _Room {
  _Room(this.id, this.code, this.host, this.expiresAt);
  final String id;
  final String code;
  String host;
  final int expiresAt;
  String status = 'lobby';
  int startsAt = 0;
  List<int> questionOrder = const [];
  int currentQ = -1;
  int qOpenedAt = 0;
  bool qResolved = false;
  int resolved = 0;
  int? lastCorrect;
  final players = <String, _Player>{};
  final answers = <String, int>{};
  final deltas = <String, int>{};

  bool get isLive =>
      status == 'lobby' || status == 'countdown' || status == 'racing';
}

/// One signed-in player's view of the fake server.
class FakeOnlineClient implements OnlineRaceService {
  FakeOnlineClient(this.server, this.me);

  final FakeOnlineServer server;
  final String me;

  /// When true every call fails as if the network dropped.
  bool offline = false;

  @override
  bool get isConfigured => true;

  OnlineResult<RoomState> _state(_Room r) =>
      OnlineResult.ok(RoomState.fromJson(server._json(r, me)));

  Future<OnlineResult<T>> _guard<T>(OnlineResult<T> Function() body) async {
    if (offline) return const OnlineResult.fail(OnlineError.offline);
    return body();
  }

  @override
  Future<OnlineResult<RoomState>> createRoom() => _guard(() {
        final id = 'room-${++server._seq}';
        String code;
        do {
          code = server._rng.nextInt(1000000).toString().padLeft(6, '0');
        } while (server._live(code) != null);
        final r = _Room(id, code, me, server.now + 30 * 60 * 1000);
        r.players[me] = _Player(1);
        server.rooms[id] = r;
        return _state(r);
      });

  @override
  Future<OnlineResult<RoomState>> join(String code) => _guard(() {
        final c = RaceCode.normalise(code);
        if (!RegExp(r'^\d{6}$').hasMatch(c)) {
          return const OnlineResult.fail('invalid_code');
        }
        final r = server._live(c);
        if (r != null) server._tick(r);
        if (r == null || !r.isLive) {
          return OnlineResult.fail(server.rooms.values.any((x) => x.code == c)
              ? 'expired'
              : 'not_found');
        }
        if (r.players.containsKey(me) && !r.players[me]!.left) return _state(r);
        if (r.status != 'lobby') {
          return const OnlineResult.fail('already_started');
        }
        final taken = r.players.values.map((p) => p.seat).toSet();
        final seat = [for (var s = 1; s <= 6; s++) s]
            .firstWhere((s) => !taken.contains(s), orElse: () => 0);
        if (seat == 0) return const OnlineResult.fail('full');
        r.players[me] = _Player(seat);
        server._invites[r.id]?.remove(me);
        return _state(r);
      });

  @override
  Future<OnlineResult<RoomState>> roomState(String roomId) => _guard(() {
        final r = server.rooms[roomId];
        if (r == null || !r.players.containsKey(me)) {
          return const OnlineResult.fail('not_member');
        }
        server._tick(r);
        return _state(r);
      });

  @override
  Future<OnlineResult<RoomState>> liveRoom() => _guard(() {
        for (final r in server.rooms.values.toList().reversed) {
          final p = r.players[me];
          if (p == null || p.left) continue;
          server._tick(r);
          if (r.isLive) return _state(r);
        }
        return const OnlineResult.fail('none');
      });

  @override
  Future<OnlineResult<RoomState>> startRace(String roomId) => _guard(() {
        final r = server.rooms[roomId]!;
        server._tick(r);
        if (r.host != me) return const OnlineResult.fail('not_host');
        if (r.status != 'lobby') {
          return const OnlineResult.fail('already_started');
        }
        if (r.players.length < 2) {
          return const OnlineResult.fail('not_enough_players');
        }
        r
          ..status = 'countdown'
          ..startsAt = server.now + FakeOnlineServer.countdownMs
          ..questionOrder = [
            for (var i = 0; i < kPracticeQuestions.length; i++) i,
          ];
        server._invites.remove(r.id);
        return _state(r);
      });

  @override
  Future<OnlineResult<AnswerOutcome>> submitAnswer(
          String roomId, int question, int option) =>
      _guard(() {
        final r = server.rooms[roomId]!;
        server._tick(r);
        final p = r.players[me];
        if (p == null) return const OnlineResult.fail('not_member');
        if (r.status != 'racing') return const OnlineResult.fail('not_racing');
        if (p.left || p.eliminated || p.finishedMs != null) {
          return const OnlineResult.fail('not_active');
        }
        if (question != r.currentQ || server.now < r.qOpenedAt) {
          return const OnlineResult.fail('wrong_question');
        }
        final ms = server.now - r.qOpenedAt;
        if (ms >= FakeOnlineServer.cfg.questionWindowMs) {
          return const OnlineResult.fail('too_late');
        }
        final key = '$me#$question';
        if (r.answers.containsKey(key)) {
          return const OnlineResult.fail('duplicate');
        }
        const cfg = FakeOnlineServer.cfg;
        final correct = option ==
            kPracticeQuestions[r.questionOrder[question]].correctIndex;
        final delta = correct
            ? (ms <= cfg.fastThresholdMs
                ? cfg.fastCorrectGain
                : cfg.correctGain)
            : -cfg.wrongPenalty;
        final next = (p.progress + delta).clamp(0, cfg.distance);
        r.answers[key] = option;
        r.deltas[key] = next - p.progress;
        final applied = next - p.progress;
        p
          ..progress = next
          ..speed = !correct
              ? 'stopped'
              : ms <= cfg.fastThresholdMs
                  ? 'fast'
                  : 'cruising'
          ..correct += correct ? 1 : 0
          ..answered += 1;
        if (next >= cfg.distance) p.finishedMs = server.now - r.startsAt;
        server._tick(r);
        return OnlineResult.ok(
            AnswerOutcome(correct: correct, delta: applied, progress: next));
      });

  @override
  Future<OnlineResult<bool>> leave(String roomId) => _guard(() {
        final r = server.rooms[roomId];
        if (r == null || !r.players.containsKey(me)) {
          return const OnlineResult.fail('not_member');
        }
        if (r.status == 'lobby') {
          r.players.remove(me);
          if (r.host == me) {
            if (r.players.isEmpty) {
              r.status = 'abandoned';
            } else {
              r.host = (r.players.entries.toList()
                    ..sort((a, b) => a.value.seat.compareTo(b.value.seat)))
                  .first
                  .key;
            }
          }
        } else if (r.isLive) {
          r.players[me]!
            ..left = true
            ..eliminated = true;
          server._tick(r);
        }
        return const OnlineResult.ok(true);
      });

  @override
  Future<OnlineResult<List<LeaderboardRow>>> leaderboard() => _guard(() {
        final stats = <String, List<int>>{};
        for (final rows in server._results.values) {
          for (final row in rows) {
            final s = stats.putIfAbsent('${row['id']}', () => [0, 0, 0]);
            final place = row['placing']! as int;
            s[0] += place == 1 ? 1 : 0;
            s[1] += place <= 3 ? 1 : 0;
            s[2] += 1;
          }
        }
        final ids = stats.keys.toList()
          ..sort((a, b) {
            final x = stats[a]!, y = stats[b]!;
            for (var i = 0; i < 3; i++) {
              final c = y[i].compareTo(x[i]);
              if (c != 0) return c;
            }
            return 0;
          });
        return OnlineResult.ok([
          for (var i = 0; i < ids.length; i++)
            LeaderboardRow(
              rank: i + 1,
              name: server._names[ids[i]]!,
              color: server._colors[ids[i]]!,
              wins: stats[ids[i]]![0],
              podiums: stats[ids[i]]![1],
              races: stats[ids[i]]![2],
              isMe: ids[i] == me,
            ),
        ]);
      });

  FriendEntry _entry(String id) =>
      FriendEntry(id: id, name: server._names[id]!, color: server._colors[id]!);

  @override
  Future<OnlineResult<FriendsSnapshot>> friends() => _guard(() {
        final l = server._links;
        String other(String k) =>
            k.split('>').firstWhere((x) => x != me, orElse: () => me);
        return OnlineResult.ok(FriendsSnapshot(
          myCode: server._friendCodes[me]!,
          friends: [
            for (final e in l.entries)
              if (e.value == 'accepted' && e.key.split('>').contains(me))
                _entry(other(e.key)),
          ],
          incoming: [
            for (final e in l.entries)
              if (e.value == 'pending' && e.key.endsWith('>$me'))
                _entry(e.key.split('>').first),
          ],
          outgoing: [
            for (final e in l.entries)
              if (e.value == 'pending' && e.key.startsWith('$me>'))
                _entry(e.key.split('>').last),
          ],
          invites: [
            for (final e in server._invites.entries)
              if (e.value.contains(me) &&
                  server.rooms[e.key]!.status == 'lobby')
                RaceInvite(
                  roomId: e.key,
                  code: server.rooms[e.key]!.code,
                  from: server._names[server.rooms[e.key]!.host]!,
                ),
          ],
        ));
      });

  @override
  Future<OnlineResult<String>> sendFriendRequest(String code) => _guard(() {
        final target = server._friendCodes.entries
            .where((e) => e.value == code.toUpperCase())
            .map((e) => e.key)
            .firstOrNull;
        if (target == null) return const OnlineResult.fail('not_found');
        if (target == me) return const OnlineResult.fail('self');
        if (server._links['$target>$me'] == 'pending') {
          server._links['$target>$me'] = 'accepted';
          return const OnlineResult.ok('accepted');
        }
        server._links['$me>$target'] ??= 'pending';
        return const OnlineResult.ok('pending');
      });

  @override
  Future<OnlineResult<bool>> respondToFriend(String friendId, bool accept) =>
      _guard(() {
        final key = '$friendId>$me';
        if (server._links[key] != 'pending') {
          return const OnlineResult.fail('not_found');
        }
        if (accept) {
          server._links[key] = 'accepted';
        } else {
          server._links.remove(key);
        }
        return const OnlineResult.ok(true);
      });

  @override
  Future<OnlineResult<bool>> removeFriend(String friendId) => _guard(() {
        server._links
          ..remove('$me>$friendId')
          ..remove('$friendId>$me');
        return const OnlineResult.ok(true);
      });

  @override
  Future<OnlineResult<bool>> inviteFriend(String roomId, String friendId) =>
      _guard(() {
        final friends = server._links['$me>$friendId'] == 'accepted' ||
            server._links['$friendId>$me'] == 'accepted';
        if (!friends) return const OnlineResult.fail('not_friends');
        server._invites.putIfAbsent(roomId, () => {}).add(friendId);
        return const OnlineResult.ok(true);
      });
}
