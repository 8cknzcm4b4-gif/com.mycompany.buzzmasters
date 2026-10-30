import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../backend/bm_firebase.dart';
import '../player/player_profile.dart';
import 'online_race_service.dart';
import 'room_view.dart';

/// [OnlineRaceService] backed by Firebase.
///
/// Every action is one `apiCall` Cloud Function call (functions/src/api.ts);
/// the server judges answers, owns the clock and ranks the race. Rooms are
/// watched live through Firestore (members-only by the security rules), so
/// the app redraws from snapshots and calls the server only to act, to send
/// a heartbeat every few seconds, and when a timer is due.
class FirebaseOnlineRaceService implements OnlineRaceService {
  FirebaseOnlineRaceService();

  bool _profileSynced = false;

  /// Server clock minus local clock, from the last server reply.
  int _skewMs = 0;
  final _watches = <String, _RoomWatch>{};

  int get _serverNow => DateTime.now().millisecondsSinceEpoch + _skewMs;

  @override
  bool get isConfigured => BmFirebase.isReady;

  Future<String?> _ready() async {
    if (!BmFirebase.isReady) return OnlineError.notConfigured;
    final problem = await BmAuth.sessionProblem();
    if (problem != null) return problem;
    if (!_profileSynced) {
      final error = await syncProfile();
      if (error != null) return error;
    }
    return null;
  }

  Future<Map<String, dynamic>> _invoke(
      String op, Map<String, dynamic> args) async {
    final res = await BmFirebase.functions
        .httpsCallable('apiCall')
        .call<Object?>({'op': op, 'args': args});
    final data = res.data;
    if (data is! Map) throw StateError('bad_reply');
    final json = data.map((k, v) => MapEntry('$k', v));
    final serverNow = json['server_now'];
    if (serverNow is num) {
      _skewMs = serverNow.toInt() - DateTime.now().millisecondsSinceEpoch;
    }
    return json;
  }

  /// Pushes the local racing name and colour to the server profile.
  Future<String?> syncProfile() async {
    final me = PlayerProfileStore.current.value;
    try {
      final json = await _invoke(
          'upsertProfile', {'name': me.name, 'color': me.colorIndex});
      if (json['ok'] != true) return '${json['error']}';
      _profileSynced = true;
      return null;
    } on Object {
      return OnlineError.offline;
    }
  }

  Future<OnlineResult<T>> _call<T>(
    String op,
    Map<String, dynamic> args,
    T Function(Map<String, dynamic> json) parse,
  ) async {
    final notReady = await _ready();
    if (notReady != null) return OnlineResult.fail(notReady);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final json = await _invoke(op, args);
        if (json['ok'] == false && json['error'] == 'no_profile' &&
            attempt == 0) {
          // The server lost this player's profile (e.g. after a sign-in
          // change): recreate it once and retry.
          _profileSynced = false;
          final error = await syncProfile();
          if (error != null) return OnlineResult.fail(error);
          continue;
        }
        if (json['ok'] == false) return OnlineResult.fail('${json['error']}');
        return OnlineResult.ok(parse(json));
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'unauthenticated') {
          return const OnlineResult.fail(OnlineError.signInFailed);
        }
        return OnlineResult.fail(
            e.code == 'unavailable' || e.code == 'deadline-exceeded'
                ? OnlineError.offline
                : 'server_error');
      } on Object {
        return const OnlineResult.fail(OnlineError.offline);
      }
    }
    return const OnlineResult.fail(OnlineError.offline);
  }

  OnlineResult<RoomState> _watching(OnlineResult<RoomState> r) {
    final room = r.value;
    if (room != null) _watch(room.roomId);
    return r;
  }

  _RoomWatch _watch(String roomId) =>
      _watches.putIfAbsent(roomId, () => _RoomWatch(roomId, BmAuth.uid ?? ''));

  @override
  Future<OnlineResult<RoomState>> createRoom() async => _watching(
      await _call('createRoom', const {}, RoomState.fromJson));

  @override
  Future<OnlineResult<RoomState>> join(String code) async => _watching(
      await _call('joinRoom', {'code': RaceCode.normalise(code)},
          RoomState.fromJson));

  @override
  Future<OnlineResult<RoomState>> quickJoin() async =>
      _watching(await _call('quickJoin', const {}, RoomState.fromJson));

  /// Live view from the Firestore snapshot when it is current; otherwise
  /// (first look, heartbeat due every 5 s, or a timer due) asks the server,
  /// which ticks the room and returns the authoritative state.
  @override
  Future<OnlineResult<RoomState>> roomState(String roomId) async {
    final w = _watch(roomId);
    final doc = w.doc;
    final now = _serverNow;
    final deadline = doc == null ? null : nextDeadline(doc);
    final due = doc == null ||
        now - w.lastServerCall > 5000 ||
        (deadline != null && now >= deadline);
    if (due && now - w.lastServerCall > 600) {
      w.lastServerCall = now;
      return _call('roomState', {'roomId': roomId}, RoomState.fromJson);
    }
    if (doc == null) return const OnlineResult.fail(OnlineError.offline);
    return OnlineResult.ok(RoomState.fromJson(
        roomViewFromDoc(doc, roomId, w.uid, w.mine, now)));
  }

  @override
  Stream<void> roomChanges(String roomId) {
    if (!BmFirebase.isReady) return const Stream.empty();
    return _watch(roomId).changes;
  }

  @override
  Future<OnlineResult<RoomState>> liveRoom() async =>
      _watching(await _call('myLiveRoom', const {}, RoomState.fromJson));

  @override
  Future<OnlineResult<RoomState>> startRace(String roomId) =>
      _call('startRace', {'roomId': roomId}, RoomState.fromJson);

  @override
  Future<OnlineResult<RoomState>> setReady(String roomId, bool ready) =>
      _call('setReady', {'roomId': roomId, 'ready': ready},
          RoomState.fromJson);

  @override
  Future<OnlineResult<AnswerOutcome>> submitAnswer(
          String roomId, int question, int option) =>
      _call(
        'submitAnswer',
        {'roomId': roomId, 'question': question, 'option': option},
        (j) => AnswerOutcome(
          correct: j['correct'] == true,
          delta: (j['delta'] as num?)?.toInt() ?? 0,
          progress: (j['progress'] as num?)?.toInt() ?? 0,
        ),
      );

  @override
  Future<OnlineResult<bool>> leave(String roomId) async {
    final r = await _call('leaveRoom', {'roomId': roomId}, (_) => true);
    _watches.remove(roomId)?.dispose();
    return r;
  }

  @override
  Future<OnlineResult<bool>> reportQuestion(String roomId, int questionIndex,
          QuestionReportReason reason) =>
      _call(
          'reportQuestion',
          {'roomId': roomId, 'question': questionIndex, 'reason': reason.wire},
          (_) => true);

  @override
  Future<OnlineResult<List<LeaderboardRow>>> leaderboard(
          {LeaderboardPeriod period = LeaderboardPeriod.allTime}) =>
      _call(
        'leaderboard',
        {'period': period.wire, 'limit': 50},
        (j) => [
          for (final r in (j['rows'] as List?) ?? const [])
            LeaderboardRow.fromJson(
                (r as Map).map((k, v) => MapEntry('$k', v))),
        ],
      );

  @override
  Future<OnlineResult<FriendsSnapshot>> friends() =>
      _call('friends', const {}, FriendsSnapshot.fromJson);

  @override
  Future<OnlineResult<String>> sendFriendRequest(String code) => _call(
      'sendFriendRequest', {'code': code.trim()}, (j) => '${j['status']}');

  @override
  Future<OnlineResult<bool>> respondToFriend(String friendId, bool accept) =>
      _call('respondFriendRequest', {'requester': friendId, 'accept': accept},
          (_) => true);

  @override
  Future<OnlineResult<bool>> removeFriend(String friendId) =>
      _call('removeFriend', {'friend': friendId}, (_) => true);

  @override
  Future<OnlineResult<bool>> inviteFriend(String roomId, String friendId) =>
      _call('inviteFriend', {'roomId': roomId, 'friend': friendId},
          (_) => true);

  @override
  Future<OnlineResult<bool>> blockPlayer(String playerId) =>
      _call('blockPlayer', {'player': playerId}, (_) => true);

  @override
  Future<OnlineResult<bool>> reportPlayer(
          String playerId, PlayerReportReason reason,
          {String? roomId}) =>
      _call('reportPlayer',
          {'target': playerId, 'reason': reason.wire, 'roomId': roomId},
          (_) => true);
}

/// A live Firestore watch of one room and of the player's own answer.
class _RoomWatch {
  _RoomWatch(this.roomId, this.uid) {
    final db = FirebaseFirestore.instance;
    _subs = [
      db.doc('rooms/$roomId').snapshots().listen((s) {
        doc = s.data();
        _changes.add(null);
      }, onError: (_) {}),
      if (uid.isNotEmpty)
        db.doc('rooms/$roomId/mine/$uid').snapshots().listen((s) {
          mine = s.data();
          _changes.add(null);
        }, onError: (_) {}),
    ];
  }

  final String roomId;
  final String uid;
  Map<String, dynamic>? doc;
  Map<String, dynamic>? mine;
  int lastServerCall = 0;
  late final List<StreamSubscription<Object?>> _subs;
  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_changes.close());
  }
}
