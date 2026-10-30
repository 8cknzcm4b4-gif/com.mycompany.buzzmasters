import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/bm_supabase.dart';
import '../player/player_profile.dart';
import 'online_race_service.dart';

/// [OnlineRaceService] backed by the Buzz Masters Supabase project.
///
/// Every call is one RPC from supabase/migrations/20261030000100_multiplayer
/// .sql; the server judges answers, owns the clock and ranks the race.
class SupabaseOnlineRaceService implements OnlineRaceService {
  SupabaseOnlineRaceService();

  bool _profileSynced = false;

  @override
  bool get isConfigured => BmSupabase.isReady;

  /// Signs in (as a guest if needed) and makes sure the server has this
  /// player's racing name and colour.
  Future<String?> _ready() async {
    if (!BmSupabase.isReady) return OnlineError.notConfigured;
    final problem = await BmAuth.sessionProblem();
    if (problem != null) return problem;
    if (!_profileSynced) {
      final error = await syncProfile();
      if (error != null) return error;
    }
    return null;
  }

  /// Pushes the local racing name and colour to the server profile.
  Future<String?> syncProfile() async {
    final me = PlayerProfileStore.current.value;
    try {
      final raw = await BmSupabase.client.rpc('bm_upsert_profile',
          params: {'p_name': me.name, 'p_color': me.colorIndex});
      final json = (raw as Map).cast<String, dynamic>();
      if (json['ok'] != true) return '${json['error']}';
      _profileSynced = true;
      return null;
    } on Object {
      return OnlineError.offline;
    }
  }

  Future<OnlineResult<T>> _call<T>(
    String fn,
    Map<String, dynamic> params,
    T Function(Map<String, dynamic> json) parse,
  ) async {
    final notReady = await _ready();
    if (notReady != null) return OnlineResult.fail(notReady);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final raw = await BmSupabase.client.rpc(fn, params: params);
        final json = (raw as Map).cast<String, dynamic>();
        if (json['ok'] != true) return OnlineResult.fail('${json['error']}');
        return OnlineResult.ok(parse(json));
      } on PostgrestException catch (e) {
        // The server lost this player's profile (e.g. after a sign-in
        // change): recreate it once and retry.
        if (e.message.contains('no_profile') && attempt == 0) {
          _profileSynced = false;
          final error = await syncProfile();
          if (error != null) return OnlineResult.fail(error);
          continue;
        }
        if (e.message.contains('not_authenticated')) {
          return const OnlineResult.fail(OnlineError.signInFailed);
        }
        return OnlineResult.fail(e.code ?? 'server_error');
      } on Object {
        return const OnlineResult.fail(OnlineError.offline);
      }
    }
    return const OnlineResult.fail(OnlineError.offline);
  }

  @override
  Future<OnlineResult<RoomState>> createRoom() =>
      _call('bm_create_room', const {}, RoomState.fromJson);

  @override
  Future<OnlineResult<RoomState>> join(String code) => _call(
      'bm_join_room', {'p_code': RaceCode.normalise(code)}, RoomState.fromJson);

  @override
  Future<OnlineResult<RoomState>> roomState(String roomId) =>
      _call('bm_room_state', {'p_room': roomId}, RoomState.fromJson);

  @override
  Future<OnlineResult<RoomState>> liveRoom() =>
      _call('bm_my_live_room', const {}, RoomState.fromJson);

  @override
  Future<OnlineResult<RoomState>> startRace(String roomId) =>
      _call('bm_start_race', {'p_room': roomId}, RoomState.fromJson);

  @override
  Future<OnlineResult<AnswerOutcome>> submitAnswer(
          String roomId, int question, int option) =>
      _call(
        'bm_submit_answer',
        {'p_room': roomId, 'p_question': question, 'p_option': option},
        (j) => AnswerOutcome(
          correct: j['correct'] == true,
          delta: (j['delta'] as num?)?.toInt() ?? 0,
          progress: (j['progress'] as num?)?.toInt() ?? 0,
        ),
      );

  @override
  Future<OnlineResult<bool>> leave(String roomId) =>
      _call('bm_leave_room', {'p_room': roomId}, (_) => true);

  @override
  Future<OnlineResult<List<LeaderboardRow>>> leaderboard() => _call(
        'bm_leaderboard',
        {'p_limit': 50},
        (j) => [
          for (final r in (j['rows'] as List?) ?? const [])
            LeaderboardRow.fromJson((r as Map).cast<String, dynamic>()),
        ],
      );

  @override
  Future<OnlineResult<FriendsSnapshot>> friends() =>
      _call('bm_friends', const {}, FriendsSnapshot.fromJson);

  @override
  Future<OnlineResult<String>> sendFriendRequest(String code) => _call(
      'bm_send_friend_request',
      {'p_code': code.trim()},
      (j) => '${j['status']}');

  @override
  Future<OnlineResult<bool>> respondToFriend(String friendId, bool accept) =>
      _call('bm_respond_friend_request',
          {'p_requester': friendId, 'p_accept': accept}, (_) => true);

  @override
  Future<OnlineResult<bool>> removeFriend(String friendId) =>
      _call('bm_remove_friend', {'p_friend': friendId}, (_) => true);

  @override
  Future<OnlineResult<bool>> inviteFriend(String roomId, String friendId) =>
      _call('bm_invite_friend', {'p_room': roomId, 'p_friend': friendId},
          (_) => true);
}
