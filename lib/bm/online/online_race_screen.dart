import 'dart:async';

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../player/player_profile.dart';
import '../race/countdown_badge.dart';
import '../race/finish_confetti.dart';
import '../race/race_arena.dart';
import '../race/race_model.dart';
import '../race/race_sound.dart';
import '../settings/bm_music.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/race_podium.dart';
import '../widgets/studio_background.dart';
import 'online_race_service.dart';

/// A live online race. The server owns the clock, judges every answer and
/// ranks the field; this screen polls its state, animates it, and sends the
/// player's answers. Connection drops show a reconnecting banner and the
/// race resumes from the server's state when the link returns.
class OnlineRaceScreen extends StatefulWidget {
  const OnlineRaceScreen({
    super.key,
    required this.initial,
    this.pollInterval = const Duration(milliseconds: 700),
  });

  final RoomState initial;
  final Duration pollInterval;

  @override
  State<OnlineRaceScreen> createState() => _OnlineRaceScreenState();
}

class _OnlineRaceScreenState extends State<OnlineRaceScreen> {
  late RoomState _room = widget.initial;
  DateTime _fetchedAt = DateTime.now();
  Timer? _poll;
  Timer? _frame;
  bool _fetching = false;
  bool _reconnecting = false;
  bool _left = false;
  bool _recorded = false;

  /// The player's pick for the open question, before the server confirms.
  int? _picked;
  int? _pickedFor;
  AnswerOutcome? _outcome;

  /// The previous question, kept to reveal its answer between questions.
  RoomQuestion? _lastQuestion;
  int _lastCountdownSecond = -1;

  @override
  void initState() {
    super.initState();
    unawaited(BmMusic.stop());
    _apply(widget.initial);
    _poll = Timer.periodic(widget.pollInterval, (_) => _refresh());
    _frame = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _frame?.cancel();
    unawaited(BmMusic.start());
    super.dispose();
  }

  int get _sinceFetch => DateTime.now().difference(_fetchedAt).inMilliseconds;

  Future<void> _refresh() async {
    if (_fetching || _left) return;
    _fetching = true;
    final result = await OnlineRace.service.roomState(_room.roomId);
    _fetching = false;
    if (!mounted || _left) return;
    final room = result.value;
    if (room == null) {
      setState(() => _reconnecting = result.error != 'not_member');
      if (result.error == 'not_member') _exit();
      return;
    }
    setState(() {
      _reconnecting = false;
      _apply(room);
    });
  }

  void _apply(RoomState room) {
    final previous = _room;
    final q = room.question;
    if (q != null) _lastQuestion = q;
    if (q == null || q.index != _pickedFor) {
      if (q != null) {
        _picked = null;
        _pickedFor = null;
        _outcome = null;
      }
    }
    // Cues on state changes.
    if (room.status == RoomStatus.countdown && room.countdownMs != null) {
      final second = (room.countdownMs! / 1000).ceil();
      if (second != _lastCountdownSecond) {
        _lastCountdownSecond = second;
        unawaited(RaceSound.countdownTick());
      }
    }
    if (previous.status == RoomStatus.countdown &&
        room.status == RoomStatus.racing) {
      unawaited(RaceSound.go());
    }
    if (room.status == RoomStatus.finished && !_recorded) {
      _recorded = true;
      unawaited(RaceSound.finish());
      final mine = room.results?.where((r) => r.isMe).firstOrNull;
      if (mine != null) {
        unawaited(PlayerProfileStore.recordRace(
          placing: mine.placing,
          correctAnswers: mine.correct,
          answeredQuestions: mine.answered,
        ));
      }
    }
    final wasOut = previous.me?.eliminated ?? false;
    if (!wasOut && (room.me?.eliminated ?? false)) {
      unawaited(RaceSound.eliminated());
    }
    _room = room;
    _fetchedAt = DateTime.now();
  }

  Future<void> _pick(RoomQuestion q, int option) async {
    if (_pickedFor == q.index || _room.myAnswer != null) return;
    setState(() {
      _picked = option;
      _pickedFor = q.index;
    });
    final result =
        await OnlineRace.service.submitAnswer(_room.roomId, q.index, option);
    if (!mounted) return;
    final outcome = result.value;
    if (outcome == null) {
      if (result.error != 'duplicate') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: BmColors.panel,
          content: Text(result.message, style: BmText.body(12.5)),
        ));
      }
      return;
    }
    setState(() => _outcome = outcome);
    unawaited(
        outcome.correct ? RaceSound.answerCorrect() : RaceSound.answerWrong());
    unawaited(_refresh());
  }

  Future<void> _confirmLeave() async {
    if (!_room.isLive) {
      _exit();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BmColors.panel,
        title: Text('LEAVE THE RACE?', style: BmText.display(18)),
        content: Text(
          'Leaving forfeits this race. The others race on without you.',
          style: BmText.body(13, color: BmColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('STAY', style: BmText.label(11, color: BmColors.cyan)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('LEAVE', style: BmText.label(11, color: BmColors.red)),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    await OnlineRace.service.leave(_room.roomId);
    _exit();
  }

  void _exit() {
    _left = true;
    _poll?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final finished = room.status == RoomStatus.finished;
    final leader =
        room.players.fold<int>(0, (m, p) => p.progress > m ? p.progress : m);
    return PopScope(
      canPop: _left || !room.isLive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: StudioScaffold(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        showAudience: false,
        intensity: finished ? 1 : 0.3 + 0.7 * leader / room.distance,
        child: Column(
          children: [
            ArenaHeader(
              title: 'ONLINE RACE',
              subtitle: 'CODE ${room.code} · ${room.players.length} RACERS',
              titleColor: BmColors.gold,
              onBack: _confirmLeave,
            ),
            if (_reconnecting)
              Container(
                key: const ValueKey('online-reconnecting'),
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: BmColors.red.withValues(alpha: 0.2),
                  border: Border.all(color: BmColors.red),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: BmColors.red),
                    ),
                    const SizedBox(width: 8),
                    Text('RECONNECTING…',
                        style: BmText.label(10, color: Colors.white)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: finished && room.results != null
                  ? Stack(children: [
                      _results(room),
                      const Positioned.fill(child: FinishConfetti()),
                    ])
                  : room.status == RoomStatus.abandoned
                      ? _abandoned()
                      : LayoutBuilder(
                          builder: (context, box) {
                            final trackH = (box.maxHeight * 0.46)
                                .clamp(200.0, 380.0)
                                .toDouble();
                            return Column(
                              children: [
                                SizedBox(height: trackH, child: _arena(room)),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: SingleChildScrollView(
                                      child: _questionArea(room)),
                                ),
                              ],
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _arena(RoomState room) {
    final counting = room.status == RoomStatus.countdown;
    final secondsLeft =
        ((room.countdownMs ?? 0) - _sinceFetch).clamp(0, 99999) / 1000;
    final ordered = [...room.players]..sort((a, b) => a.seat.compareTo(b.seat));
    return RaceArena(
      distance: room.distance,
      positions: counting ? const {} : room.positions,
      running: room.status == RoomStatus.racing,
      finished: room.status == RoomStatus.finished,
      hudLabel:
          counting ? 'GRID' : 'Q ${room.questionNumber} / ${room.maxQuestions}',
      overlay: counting ? RaceCountdown(secondsLeft: secondsLeft.ceil()) : null,
      onPlayerOvertake: () => unawaited(RaceSound.overtake()),
      racers: [
        for (final p in ordered)
          ArenaRacer(
            id: p.id,
            name: p.connected || p.left ? p.name : '${p.name} ⚠',
            color: BmColors.seatColors[p.color % BmColors.seatColors.length],
            progress: p.progress,
            speed: switch (p.speed) {
              'fast' => SpeedStatus.fast,
              'cruising' => SpeedStatus.cruising,
              _ => SpeedStatus.stopped,
            },
            finished: p.finished,
            eliminated: p.eliminated,
            danger: p.danger,
            isPlayer: p.isMe,
          ),
      ],
    );
  }

  Widget _questionArea(RoomState room) {
    final me = room.me;
    if (room.status == RoomStatus.countdown) {
      return _info(
          Icons.bolt_rounded,
          BmColors.cyan,
          'ANSWER FAST TO ACCELERATE',
          'Every racer gets the same question at the same moment. The server '
              'times and judges each answer.');
    }
    if (me != null && (me.eliminated || me.left)) {
      return _info(Icons.visibility_rounded, BmColors.red, 'SPECTATING',
          'You are OUT. The race continues without you.');
    }
    if (me != null && me.finished) {
      return _info(Icons.sports_score_rounded, BmColors.gold, 'FINISHED!',
          'Waiting for the race to end…');
    }
    final q = room.question;
    if (q == null) {
      final last = _lastQuestion;
      final idx = room.lastCorrectIndex;
      return BmPanel(
        child: Column(
          children: [
            Text('NEXT QUESTION…',
                style: BmText.label(12, color: BmColors.cyan)),
            if (last != null && idx != null && idx < last.options.length) ...[
              const SizedBox(height: 8),
              Text('Answer: ${last.options[idx]}',
                  key: const ValueKey('online-reveal'),
                  style: BmText.body(14,
                      color: BmColors.gold, weight: FontWeight.w600)),
            ],
          ],
        ),
      );
    }

    final leftMs = (q.remainingMs - _sinceFetch).clamp(0, room.windowMs);
    final mine =
        room.myAnswer?.option ?? (_pickedFor == q.index ? _picked : null);
    final verdict = room.myAnswer?.correct ?? _outcome?.correct;
    return BmPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        children: [
          Row(
            children: [
              // Wraps so long categories never overflow a narrow phone.
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    BmChip(text: q.category, color: BmColors.cyan),
                    BmChip(text: q.difficulty, color: BmColors.purple),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TimerRing(
                  secondsLeft: leftMs / 1000,
                  total: room.windowMs / 1000,
                  size: 46),
            ],
          ),
          const SizedBox(height: 8),
          Text(q.prompt,
              textAlign: TextAlign.center,
              style: BmText.title(18).copyWith(height: 1.3)),
          const SizedBox(height: 6),
          SizedBox(
            height: 20,
            child: verdict == null
                ? null
                : Text(
                    verdict
                        ? 'Correct! +${(_outcome?.delta ?? room.myAnswer?.delta ?? 0)}'
                        : 'Wrong answer',
                    style: BmText.body(12,
                        color: verdict ? BmColors.green : BmColors.red,
                        weight: FontWeight.w600),
                  ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AnswerTile(
                letter: String.fromCharCode(65 + i),
                text: q.options[i],
                selected: mine == i,
                correct: mine == i && verdict == true,
                wrong: mine == i && verdict == false,
                enabled: mine == null && leftMs > 0,
                onTap: () => _pick(q, i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _info(IconData icon, Color color, String title, String body) =>
      BmPanel(
        color: color,
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(title,
                textAlign: TextAlign.center,
                style: BmText.display(17, color: color)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: BmText.body(12.5, color: BmColors.muted)),
          ],
        ),
      );

  Widget _abandoned() => Center(
        child: _info(Icons.cloud_off_rounded, BmColors.gold, 'RACE CLOSED',
            'Everyone left before the finish, so this race was abandoned.'),
      );

  Widget _results(RoomState room) {
    final results = room.results!;
    final mine = results.where((r) => r.isMe).firstOrNull;
    Color color(RoomResult r) =>
        BmColors.seatColors[r.color % BmColors.seatColors.length];
    String detail(RoomResult r) => r.finished
        ? 'FINISHED'
        : r.eliminated
            ? 'OUT'
            : '${r.progress} / ${room.distance}';
    return Column(
      children: [
        Text('RESULTS', style: BmText.display(26, color: BmColors.gold)),
        if (mine != null)
          Text(
            mine.placing == 1
                ? 'YOU WIN THE RACE!'
                : 'YOU FINISHED P${mine.placing}',
            style: BmText.label(11, color: Colors.white),
          ),
        const SizedBox(height: 4),
        RacePodium(
          height: 220,
          entries: [
            for (final r in results.take(3))
              PodiumEntry(
                name: r.name,
                color: color(r),
                detail: detail(r),
                isPlayer: r.isMe,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final r in results.skip(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: BmPanel(
                    color: r.isMe ? BmColors.gold : BmColors.panelEdge,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(
                      children: [
                        Text('P${r.placing}',
                            style: BmText.display(15, color: BmColors.muted)),
                        const SizedBox(width: 12),
                        CircleAvatar(radius: 5, backgroundColor: color(r)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(r.name, style: BmText.title(14))),
                        Text(detail(r), style: BmText.label(10)),
                      ],
                    ),
                  ),
                ),
              if (mine != null)
                BmPanel(
                  color: BmColors.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _stat('PLACE', 'P${mine.placing}'),
                      _stat('CORRECT', '${mine.correct}/${mine.answered}'),
                      _stat('DISTANCE', '${mine.progress}'),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        BmButton(
          label: 'BACK TO LOBBY',
          icon: Icons.arrow_back_rounded,
          style: BmButtonStyle.outline,
          height: 48,
          onPressed: _exit,
        ),
      ],
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(value, style: BmText.display(18)),
          Text(label, style: BmText.label(8, color: BmColors.cyan)),
        ],
      );
}
