import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/bm_theme.dart';
import '../online/join_game_screen.dart';
import '../online/online_lobby_screen.dart';
import '../online/online_race_service.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';

/// Friends and race invitations, stored on the Buzz Masters server: your
/// friend code, adding friends by theirs, requests, and invites into lobbies.
/// Without a server it says so and points to joining by race code.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, this.showBack = true});

  final bool showBack;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late Future<OnlineResult<FriendsSnapshot>> _load = _fetch();
  final _code = TextEditingController();
  bool _sending = false;

  Future<OnlineResult<FriendsSnapshot>> _fetch() =>
      OnlineRace.service.friends();

  void _reload() {
    final next = _fetch();
    setState(() {
      _load = next;
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: BmColors.panel,
        content: Text(text, style: BmText.body(12.5)),
      ));

  Future<void> _add() async {
    final code = _code.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      _say('Friend codes are 6 letters and numbers.');
      return;
    }
    setState(() => _sending = true);
    final r = await OnlineRace.service.sendFriendRequest(code);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!r.ok) {
      _say(r.error == 'not_found'
          ? 'No racer has that friend code.'
          : r.message);
      return;
    }
    _code.clear();
    _say(r.value == 'accepted'
        ? 'You are now friends!'
        : 'Friend request sent.');
    _reload();
  }

  Future<void> _respond(FriendEntry f, bool accept) async {
    final r = await OnlineRace.service.respondToFriend(f.id, accept);
    if (!mounted) return;
    if (!r.ok) _say(r.message);
    _reload();
  }

  Future<void> _joinInvite(RaceInvite invite) async {
    final r = await OnlineRace.service.join(invite.code);
    if (!mounted) return;
    final room = r.value;
    if (room == null) {
      _say(r.message);
      _reload();
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => onlineRoomScreen(room)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          ArenaHeader(
            title: 'FRIENDS',
            subtitle: 'INVITES & PRIVATE RACES',
            showBack: widget.showBack,
            trailing: OnlineRace.service.isConfigured
                ? BmIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh',
                    onPressed: _reload,
                  )
                : null,
          ),
          Expanded(
            child: OnlineRace.service.isConfigured ? _online() : _offline(),
          ),
        ],
      ),
    );
  }

  Widget _online() {
    return FutureBuilder<OnlineResult<FriendsSnapshot>>(
      future: _load,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(color: BmColors.cyan));
        }
        final result = snap.data!;
        final data = result.value;
        if (data == null) {
          return _state(Icons.cloud_off_rounded, BmColors.red,
              'COULD NOT LOAD FRIENDS', result.message,
              action:
                  BmButton(label: 'TRY AGAIN', height: 46, onPressed: _reload));
        }
        return ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            BmPanel(
              color: BmColors.gold,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('YOUR FRIEND CODE',
                            style: BmText.label(9, color: BmColors.gold)),
                        Text(data.myCode,
                            key: const ValueKey('my-friend-code'),
                            style:
                                BmText.display(28).copyWith(letterSpacing: 5)),
                      ],
                    ),
                  ),
                  BmIconButton(
                    icon: Icons.copy_rounded,
                    color: BmColors.gold,
                    tooltip: 'Copy friend code',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: data.myCode));
                      _say('Friend code copied.');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            BmPanel(
              color: BmColors.cyan,
              padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('friend-code-field'),
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      style: BmText.display(20).copyWith(letterSpacing: 4),
                      decoration: InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        hintText: 'ADD BY CODE',
                        hintStyle: BmText.label(12, color: BmColors.muted),
                      ),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  BmButton(
                    label: _sending ? '…' : 'ADD',
                    style: BmButtonStyle.cyan,
                    height: 40,
                    fontSize: 12,
                    expand: false,
                    onPressed: _sending ? null : _add,
                  ),
                ],
              ),
            ),
            if (data.invites.isNotEmpty) ...[
              _title('RACE INVITES'),
              for (final i in data.invites)
                _row(
                  name: '${i.from} invited you',
                  sub: 'Race code ${i.code}',
                  color: BmColors.gold,
                  trailing: TextButton(
                    onPressed: () => _joinInvite(i),
                    child: Text('JOIN',
                        style: BmText.label(10, color: BmColors.gold)),
                  ),
                ),
            ],
            if (data.incoming.isNotEmpty) ...[
              _title('FRIEND REQUESTS'),
              for (final f in data.incoming)
                _row(
                  name: f.name,
                  sub: 'Wants to be friends',
                  color: BmColors.seatColors[f.color % 6],
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Decline',
                        onPressed: () => _respond(f, false),
                        icon: const Icon(Icons.close_rounded,
                            color: BmColors.red),
                      ),
                      IconButton(
                        tooltip: 'Accept',
                        onPressed: () => _respond(f, true),
                        icon: const Icon(Icons.check_rounded,
                            color: BmColors.green),
                      ),
                    ],
                  ),
                ),
            ],
            _title('FRIENDS · ${data.friends.length}'),
            if (data.friends.isEmpty)
              Text(
                'Share your friend code, or add a friend with theirs. Friends '
                'can invite each other straight into a race lobby.',
                style: BmText.body(12.5, color: BmColors.muted),
              ),
            for (final f in data.friends)
              _row(
                name: f.name,
                sub: 'Friend',
                color: BmColors.seatColors[f.color % 6],
                trailing: IconButton(
                  tooltip: 'Remove friend',
                  onPressed: () async {
                    await OnlineRace.service.removeFriend(f.id);
                    if (mounted) _reload();
                  },
                  icon: const Icon(Icons.person_remove_rounded,
                      color: BmColors.muted),
                ),
              ),
            for (final f in data.outgoing)
              _row(
                name: f.name,
                sub: 'Request sent',
                color: BmColors.seatColors[f.color % 6],
              ),
          ],
        );
      },
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text, style: BmText.label(10, color: Colors.white)),
      );

  Widget _row({
    required String name,
    required String sub,
    required Color color,
    Widget? trailing,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: BmPanel(
          color: BmColors.panelEdge,
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color,
                child: Text(name.characters.first.toUpperCase(),
                    style: BmText.display(15, color: BmColors.deep)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BmText.title(14)),
                    Text(sub, style: BmText.body(11, color: BmColors.muted)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      );

  Widget _offline() => _state(
        Icons.people_alt_rounded,
        BmColors.violet,
        'FRIENDS NEED ONLINE PLAY',
        'Friend lists, invitations and private races are stored on the Buzz '
            'Masters server, which this build is not connected to yet. '
            'Nothing is shown rather than placeholder friends.',
        action: BmButton(
          label: 'JOIN WITH CODE',
          icon: Icons.login_rounded,
          style: BmButtonStyle.cyan,
          height: 48,
          fontSize: 13,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const JoinGameScreen()),
          ),
        ),
      );

  Widget _state(IconData icon, Color color, String title, String body,
          {Widget? action}) =>
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(top: 30),
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.18),
                  border: Border.all(color: color),
                  boxShadow: bmGlow(color, blur: 30, opacity: 0.4),
                ),
                child: Icon(icon, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center, style: BmText.display(21)),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: BmText.body(13, color: BmColors.muted)),
              if (action != null) ...[const SizedBox(height: 22), action],
            ],
          ),
        ),
      );
}
