import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/bm_theme.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';
import 'online_race_screen.dart';
import 'online_race_service.dart';

/// The right screen for a room in its current state.
Widget onlineRoomScreen(RoomState room) => room.status == RoomStatus.lobby
    ? OnlineLobbyScreen(initial: room)
    : OnlineRaceScreen(initial: room);

/// A live online lobby: up to six seats filled by the server, the race code
/// to share, friend invites, and the host's start button.
class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({
    super.key,
    required this.initial,
    this.pollInterval = const Duration(seconds: 1),
  });

  final RoomState initial;
  final Duration pollInterval;

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  late RoomState _room = widget.initial;
  Timer? _poll;
  StreamSubscription<void>? _changes;
  bool _busy = false;
  bool _readyBusy = false;
  bool _fetching = false;
  bool _left = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(widget.pollInterval, (_) => _refresh());
    // Realtime: refetch as soon as the server changes the room; the poll
    // stays as the fallback.
    _changes = OnlineRace.service
        .roomChanges(_room.roomId)
        .listen((_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _toggleReady() async {
    final ready = !(_room.me?.ready ?? false);
    setState(() => _readyBusy = true);
    final result = await OnlineRace.service.setReady(_room.roomId, ready);
    if (!mounted) return;
    setState(() {
      _readyBusy = false;
      if (result.value != null) _room = result.value!;
    });
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(_snack(result.message));
    }
  }

  Future<void> _refresh() async {
    if (_fetching || _left) return;
    _fetching = true;
    final result = await OnlineRace.service.roomState(_room.roomId);
    _fetching = false;
    if (!mounted || _left) return;
    final room = result.value;
    if (room == null) {
      if (result.error == 'not_member') {
        _closeWith(result.message);
      } else {
        setState(() => _problem = result.message);
      }
      return;
    }
    setState(() {
      _room = room;
      _problem = null;
    });
    if (room.status == RoomStatus.abandoned) {
      _closeWith('This lobby closed.');
    } else if (room.status != RoomStatus.lobby) {
      _poll?.cancel();
      unawaited(Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
            builder: (_) => OnlineRaceScreen(initial: room)),
      ));
    }
  }

  void _closeWith(String message) {
    _left = true;
    _poll?.cancel();
    ScaffoldMessenger.of(context).showSnackBar(_snack(message));
    Navigator.of(context).maybePop();
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    final result = await OnlineRace.service.startRace(_room.roomId);
    if (!mounted) return;
    setState(() => _busy = false);
    final room = result.value;
    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(_snack(result.message));
      return;
    }
    _poll?.cancel();
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => OnlineRaceScreen(initial: room)),
    );
  }

  Future<void> _leave() async {
    _left = true;
    _poll?.cancel();
    await OnlineRace.service.leave(_room.roomId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _invite() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: BmColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _InviteSheet(roomId: _room.roomId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final bySeat = {for (final p in room.players) p.seat: p};
    final canStart = room.isHost && room.players.length >= room.minPlayers;
    final readyCount = room.players.where((p) => p.ready && !p.left).length;
    final iAmReady = room.me?.ready ?? false;
    return PopScope(
      canPop: _left,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: StudioScaffold(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Column(
          children: [
            ArenaHeader(
              title: 'RACE LOBBY',
              subtitle: '${room.isPublic ? 'PUBLIC · ' : ''}'
                  '${room.players.length} / ${room.maxSeats} RACERS',
              onBack: _leave,
            ),
            const SizedBox(height: 8),
            _codeCard(room.code),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_problem!,
                    textAlign: TextAlign.center,
                    style: BmText.body(11.5, color: const Color(0xFFFFB3C0))),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.5,
                children: [
                  for (var seat = 1; seat <= room.maxSeats; seat++)
                    _seat(seat, bySeat[seat]),
                ],
              ),
            ),
            BmButton(
              label: 'INVITE FRIENDS',
              icon: Icons.person_add_alt_1_rounded,
              style: BmButtonStyle.violet,
              height: 46,
              fontSize: 13,
              onPressed: room.players.length < room.maxSeats ? _invite : null,
            ),
            const SizedBox(height: 10),
            if (room.isHost)
              BmButton(
                key: const ValueKey('online-start'),
                label: _busy
                    ? 'STARTING…'
                    : !canStart
                        ? 'NEED ${room.minPlayers} RACERS TO START'
                        : room.allReady
                            ? 'START RACE · ALL READY'
                            : 'START RACE · $readyCount/${room.players.length} READY',
                icon: Icons.sports_score_rounded,
                height: 54,
                onPressed: canStart && !_busy ? _start : null,
              )
            else
              BmButton(
                key: const ValueKey('lobby-ready'),
                label: _readyBusy
                    ? 'SAVING…'
                    : iAmReady
                        ? 'READY · WAITING FOR ${room.hostName.toUpperCase()}'
                        : "TAP WHEN YOU'RE READY",
                icon: iAmReady
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                style: iAmReady ? BmButtonStyle.outline : BmButtonStyle.gold,
                height: 54,
                fontSize: 13,
                onPressed: _readyBusy ? null : _toggleReady,
              ),
          ],
        ),
      ),
    );
  }

  Widget _codeCard(String code) {
    return BmPanel(
      color: BmColors.gold,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RACE CODE', style: BmText.label(9, color: BmColors.gold)),
                Text(
                  '${code.substring(0, 3)} ${code.substring(3)}',
                  key: const ValueKey('online-room-code'),
                  style: BmText.display(34).copyWith(letterSpacing: 6),
                ),
              ],
            ),
          ),
          BmIconButton(
            icon: Icons.copy_rounded,
            color: BmColors.gold,
            tooltip: 'Copy code',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context)
                  .showSnackBar(_snack('Race code $code copied.'));
            },
          ),
        ],
      ),
    );
  }

  Widget _seat(int seat, RoomPlayer? p) {
    final color = BmColors.seatColors[(p?.color ?? seat - 1) % 6];
    return BmPanel(
      color: p == null ? BmColors.panelEdge : color,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor:
                p == null ? Colors.white.withValues(alpha: 0.08) : color,
            child: Text(
              p == null ? '$seat' : p.name.characters.first.toUpperCase(),
              style: BmText.display(14,
                  color: p == null ? BmColors.muted : BmColors.deep),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p == null ? 'Open seat' : p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BmText.title(13,
                      color: p == null ? BmColors.muted : Colors.white),
                ),
                if (p != null)
                  Text(
                    p.isHost
                        ? (p.isMe ? 'HOST · YOU' : 'HOST')
                        : !p.connected
                            ? 'RECONNECTING'
                            : '${p.isMe ? 'YOU · ' : ''}'
                                '${p.ready ? 'READY' : 'NOT READY'}',
                    key: ValueKey('seat-status-${p.seat}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BmText.label(7.5,
                        color: p.isHost
                            ? BmColors.gold
                            : !p.connected
                                ? BmColors.red
                                : p.ready
                                    ? BmColors.green
                                    : BmColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.roomId});

  final String roomId;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  late final Future<OnlineResult<FriendsSnapshot>> _friends =
      OnlineRace.service.friends();
  final Set<String> _sent = {};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: FutureBuilder<OnlineResult<FriendsSnapshot>>(
          future: _friends,
          builder: (_, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 120,
                child: Center(
                    child: CircularProgressIndicator(color: BmColors.cyan)),
              );
            }
            final result = snap.data!;
            final friends = result.value?.friends ?? const <FriendEntry>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('INVITE FRIENDS', style: BmText.display(18)),
                const SizedBox(height: 10),
                if (!result.ok)
                  Text(result.message, style: BmText.body(12.5))
                else if (friends.isEmpty)
                  Text(
                    'No friends yet. Add friends by their friend code on the '
                    'Friends tab, or share the race code.',
                    style: BmText.body(12.5, color: BmColors.muted),
                  ),
                for (final f in friends)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: BmColors.seatColors[f.color % 6],
                      child: Text(f.name.characters.first.toUpperCase(),
                          style: BmText.display(14, color: BmColors.deep)),
                    ),
                    title: Text(f.name, style: BmText.title(14)),
                    trailing: _sent.contains(f.id)
                        ? Text('INVITED',
                            style: BmText.label(9, color: BmColors.green))
                        : TextButton(
                            onPressed: () async {
                              final r = await OnlineRace.service
                                  .inviteFriend(widget.roomId, f.id);
                              if (!mounted || !context.mounted) return;
                              if (r.ok) {
                                setState(() => _sent.add(f.id));
                              } else {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(_snack(r.message));
                              }
                            },
                            child: Text('INVITE',
                                style: BmText.label(10, color: BmColors.cyan)),
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

SnackBar _snack(String text) => SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: BmColors.panel,
      content: Text(text, style: BmText.body(12.5)),
    );
