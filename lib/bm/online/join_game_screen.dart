import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/bm_theme.dart';
import '../race/race_practice_screen.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';
import 'online_race_service.dart';

/// Join an online race by its six-digit code.
///
/// Every code goes to [OnlineRace.service]; this screen never decides on its
/// own that a lobby exists.
class JoinGameScreen extends StatefulWidget {
  const JoinGameScreen({super.key});

  @override
  State<JoinGameScreen> createState() => _JoinGameScreenState();
}

class _JoinGameScreenState extends State<JoinGameScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final formatError = RaceCode.validate(_controller.text);
    if (formatError != null) {
      setState(() => _error = formatError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final JoinResult result;
    try {
      result =
          await OnlineRace.service.join(RaceCode.normalise(_controller.text));
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = JoinFailure.offline.message;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final session = result.session;
    if (session == null) {
      setState(() => _error = result.failure!.message);
      return;
    }
    await OnlineRace.remember(session);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
          builder: (_) => OnlineLobbyScreen(session: session)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final configured = OnlineRace.service.isConfigured;
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          const ArenaHeader(title: 'JOIN GAME', subtitle: 'ENTER A RACE CODE'),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  const Icon(Icons.qr_code_2_rounded,
                      color: BmColors.cyan, size: 52),
                  const SizedBox(height: 10),
                  Text('Got a code from a friend?', style: BmText.display(22)),
                  const SizedBox(height: 6),
                  Text(
                    'Enter the 6-digit code shown in the host\'s lobby.',
                    textAlign: TextAlign.center,
                    style: BmText.body(13, color: BmColors.muted),
                  ),
                  const SizedBox(height: 22),
                  BmPanel(
                    color: _error != null ? BmColors.red : BmColors.cyan,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: TextField(
                      key: const ValueKey('race-code-field'),
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 7,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\s-]')),
                      ],
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onSubmitted: (_) => _join(),
                      style: BmText.display(34, color: Colors.white)
                          .copyWith(letterSpacing: 12),
                      cursorColor: BmColors.cyan,
                      decoration: InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        hintText: '000000',
                        hintStyle: BmText.display(34,
                                color: Colors.white.withValues(alpha: 0.18))
                            .copyWith(letterSpacing: 12),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _error == null
                        ? const SizedBox(width: double.infinity, height: 12)
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: BmColors.red, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    key: const ValueKey('join-error'),
                                    style: BmText.body(12.5,
                                        color: const Color(0xFFFFB3C0)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 18),
                  BmButton(
                    label: _busy ? 'CHECKING CODE…' : 'JOIN RACE',
                    icon: Icons.login_rounded,
                    onPressed: _busy ? null : _join,
                  ),
                  if (!configured) ...[
                    const SizedBox(height: 22),
                    BmPanel(
                      color: BmColors.gold,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.cloud_off_rounded,
                                  color: BmColors.gold, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text('ONLINE SERVER NOT CONNECTED',
                                      style: BmText.label(10,
                                          color: BmColors.gold))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Codes can be entered and validated, but online '
                            'lobbies need the Buzz Masters game server, which '
                            'this build is not connected to.',
                            style: BmText.body(12, color: BmColors.muted),
                          ),
                          const SizedBox(height: 10),
                          BmButton(
                            label: 'PRACTICE RACE INSTEAD',
                            icon: Icons.sports_score_rounded,
                            style: BmButtonStyle.cyan,
                            height: 46,
                            fontSize: 13,
                            onPressed: () => Navigator.of(context)
                                .pushReplacement(MaterialPageRoute<void>(
                              builder: (_) => const RacePracticeScreen(),
                            )),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A lobby the server confirmed the player is in.
class OnlineLobbyScreen extends StatelessWidget {
  const OnlineLobbyScreen({super.key, required this.session});

  final LobbySession session;

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          ArenaHeader(
            title: 'RACE LOBBY',
            subtitle: 'CODE ${session.code}',
          ),
          const SizedBox(height: 12),
          Text('Hosted by ${session.hostName}',
              style: BmText.body(13, color: BmColors.muted)),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.6,
              children: [
                for (var i = 0; i < 6; i++)
                  BmPanel(
                    color: i < session.players.length
                        ? BmColors.seatColors[i]
                        : BmColors.panelEdge,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Text('${i + 1}',
                            style: BmText.display(18,
                                color: BmColors.seatColors[i])),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            i < session.players.length
                                ? session.players[i]
                                : 'Open seat',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BmText.title(13,
                                color: i < session.players.length
                                    ? Colors.white
                                    : BmColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          BmPanel(
            color: BmColors.cyan,
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: BmColors.cyan),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Waiting for the host to start the race…',
                      style: BmText.body(13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          BmButton(
            label: 'LEAVE LOBBY',
            style: BmButtonStyle.outline,
            height: 48,
            onPressed: () async {
              await OnlineRace.forget();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
