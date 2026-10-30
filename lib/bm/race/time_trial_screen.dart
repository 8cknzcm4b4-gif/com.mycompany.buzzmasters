import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../game/practice_match.dart';
import '../screens/settings_screen.dart';
import '../settings/bm_audio_settings.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';
import 'countdown_badge.dart';
import 'race_model.dart';
import 'race_sound.dart';
import 'race_arena.dart';
import 'time_trial.dart';
import 'time_trial_store.dart';

const _racerId = 'you';
const _revealMs = 1200;

/// Solo time trial: one racer against the clock, chasing the best run's ghost.
///
/// No opponents and no danger-zone elimination, so a bad answer costs progress
/// but never ends the run. A finished run that beats the stored best replaces
/// the ghost.
class TimeTrialScreen extends StatefulWidget {
  const TimeTrialScreen({
    super.key,
    this.config = const RaceConfig(dangerZoneMax: -1),
    this.questions,
    this.store = const PrefsTimeTrialStore(),
    this.random,
  });

  final RaceConfig config;
  final List<QuizQuestion>? questions;
  final TimeTrialStore store;

  /// Injected by tests; defaults to a fresh random source.
  final Random? random;

  @override
  State<TimeTrialScreen> createState() => _TimeTrialScreenState();
}

class _TimeTrialScreenState extends State<TimeTrialScreen> {
  late final Random _rng = widget.random ?? Random();
  late final List<QuizQuestion> _questions =
      widget.questions ?? ([...kPracticeQuestions]..shuffle(_rng));

  final Stopwatch _clock = Stopwatch();
  late RaceModel _race;
  late TimeTrialRunRecorder _recorder;

  GhostTrack? _ghost;
  int _countLeft = 3;
  int _questionIndex = 0;
  int _questionOpenedMs = 0;
  int? _selected;
  int? _finishMs;
  bool _over = false;
  bool _newBest = false;
  int? _deltaMs;

  /// Guards against opening settings twice while the route is in flight.
  bool _settingsOpen = false;

  Timer? _countdownTimer;
  Timer? _windowTimer;
  Timer? _revealTimer;
  Timer? _refresh;

  QuizQuestion get _question => _questions[_questionIndex % _questions.length];
  int get _distance => widget.config.distance;
  RacerProgress get _me => _race.racers.first;

  @override
  void initState() {
    super.initState();
    unawaited(BmAudioSettings.ensureLoaded());
    _resetRace();
    unawaited(_loadGhost());
    _refresh = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
    _startCountdown();
  }

  @override
  void dispose() {
    _clock.stop();
    _countdownTimer?.cancel();
    _windowTimer?.cancel();
    _revealTimer?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  void _resetRace() {
    _clock
      ..stop()
      ..reset();
    _race = RaceModel(
      config: widget.config,
      racers: const [RacerProgress(id: _racerId)],
    ).startCountdown();
    _recorder = TimeTrialRunRecorder(distance: _distance);
    _countLeft = widget.config.countdownSeconds;
    _questionIndex = 0;
    _questionOpenedMs = 0;
    _selected = null;
    _finishMs = null;
    _over = false;
    _newBest = false;
    _deltaMs = null;
  }

  Future<void> _loadGhost() async {
    final ghost = await widget.store.loadBest();
    if (!mounted || ghost == null) return;
    setState(() => _ghost = ghost);
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _countLeft--);
      if (_countLeft <= 0) {
        timer.cancel();
        _go();
      } else {
        unawaited(RaceSound.countdownTick());
      }
    });
  }

  void _go() {
    _clock
      ..reset()
      ..start();
    unawaited(RaceSound.go());
    setState(() => _race = _race.go());
    _nextQuestion();
  }

  void _nextQuestion() {
    if (!mounted) return;
    if (_over || _me.finished || _race.phase == RacePhase.results) {
      if (!_over) _endRun();
      return;
    }
    _questionOpenedMs = _clock.elapsedMilliseconds;
    setState(() {
      _race = _race.openQuestion();
      _selected = null;
    });
    _windowTimer?.cancel();
    _windowTimer = Timer(
      Duration(milliseconds: widget.config.questionWindowMs),
      _closeWindow,
    );
  }

  void _pick(int index) {
    if (_selected != null || _over || _race.phase != RacePhase.questionActive) {
      return;
    }
    final correct = index == _question.correctIndex;
    setState(() => _selected = index);
    unawaited(correct ? RaceSound.answerCorrect() : RaceSound.answerWrong());
    _race = _race.applyAnswer(
      racerId: _racerId,
      correct: correct,
      responseMs: _clock.elapsedMilliseconds - _questionOpenedMs,
      atMs: _clock.elapsedMilliseconds,
    );
    _recorder.record(
      atMs: _clock.elapsedMilliseconds,
      progress: _me.progress,
    );
    if (_me.finished) {
      _endRun();
      return;
    }
    _closeWindow();
  }

  void _closeWindow() {
    if (!mounted || _race.phase != RacePhase.questionActive) return;
    _windowTimer?.cancel();
    final answered = _selected == null ? const <String>{} : const {_racerId};
    setState(() {
      _race = _race.applyTimeout(
        answeredIds: answered,
        atMs: _clock.elapsedMilliseconds,
      );
    });
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(milliseconds: _revealMs), () {
      _resolveAndContinue();
    });
  }

  void _resolveAndContinue() {
    if (!mounted) return;
    setState(() {
      _race = _race.resolveQuestion();
      _questionIndex++;
    });
    _recorder.record(
      atMs: _clock.elapsedMilliseconds,
      progress: _me.progress,
    );
    _nextQuestion();
  }

  /// Time left on the current question window, in milliseconds.
  int get _windowRemainingMs {
    final used = _clock.elapsedMilliseconds - _questionOpenedMs;
    final left = widget.config.questionWindowMs - used;
    return left < 0 ? 0 : left;
  }

  /// Opens settings with the run frozen. The clock, the question window and
  /// the reveal are all restarted afterwards, so changing sound or haptics
  /// mid-run never costs distance or adds time.
  Future<void> _openSettings() async {
    if (_settingsOpen) return;
    _settingsOpen = true;

    final windowLeft = _windowRemainingMs;
    final wasCountingDown = _countdownTimer?.isActive ?? false;
    final wasRevealing = _revealTimer?.isActive ?? false;
    final clockWasRunning = _clock.isRunning;

    _windowTimer?.cancel();
    _countdownTimer?.cancel();
    _revealTimer?.cancel();
    _clock.stop();
    final pausedAt = DateTime.now().millisecondsSinceEpoch;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BmSettingsScreen()),
    );
    if (!mounted) return;
    _settingsOpen = false;

    // The paused stretch must not count towards the player's response time.
    if (clockWasRunning) {
      _questionOpenedMs += DateTime.now().millisecondsSinceEpoch - pausedAt;
      _clock.start();
    }

    if (wasRevealing) {
      _revealTimer = Timer(
        const Duration(milliseconds: _revealMs),
        _resolveAndContinue,
      );
    } else if (_race.phase == RacePhase.questionActive) {
      _windowTimer = Timer(
        Duration(milliseconds: windowLeft < 600 ? 600 : windowLeft),
        _closeWindow,
      );
    } else if (wasCountingDown) {
      _startCountdown();
    }
  }

  void _endRun() {
    _countdownTimer?.cancel();
    _windowTimer?.cancel();
    _revealTimer?.cancel();
    _clock.stop();
    final elapsed = _clock.elapsedMilliseconds;
    final ghost = _ghost;
    final track = _recorder.build(elapsedMs: elapsed);
    final newBest =
        track != null && (ghost == null || elapsed < ghost.elapsedMs);
    if (newBest) unawaited(widget.store.saveBest(track));
    unawaited(RaceSound.finish());
    final finished = _me.finished;
    setState(() {
      _race = _race.finish();
      _over = true;
      _finishMs = finished ? elapsed : null;
      _newBest = newBest;
      _deltaMs = ghost == null || !finished ? null : elapsed - ghost.elapsedMs;
    });
  }

  void _restart() {
    _countdownTimer?.cancel();
    _windowTimer?.cancel();
    _revealTimer?.cancel();
    setState(_resetRace);
    _startCountdown();
  }

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          ArenaHeader(
            title: 'TIME TRIAL',
            subtitle: 'RACE YOUR BEST GHOST',
            titleColor: BmColors.gold,
            trailing: BmIconButton(
              icon: Icons.settings_rounded,
              color: BmColors.gold,
              tooltip: 'Settings',
              onPressed: _openSettings,
            ),
          ),
          const SizedBox(height: 4),
          _clockLine(),
          const SizedBox(height: 8),
          Expanded(
            child: _over
                ? _results()
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        _lanes(),
                        const SizedBox(height: 12),
                        _questionArea(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _clockLine() {
    final ghost = _ghost;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.timer_rounded, size: 14, color: BmColors.cyan),
        const SizedBox(width: 6),
        Text(
          formatRaceTime(_clock.elapsedMilliseconds),
          style: BmText.title(16),
        ),
        if (ghost != null) ...[
          const SizedBox(width: 10),
          Text(
            'BEST ${formatRaceTime(ghost.elapsedMs)}',
            style: BmText.body(12, color: BmColors.muted),
          ),
        ],
      ],
    );
  }

  Widget _lanes() {
    final me = _me;
    final ghostProgress = _ghost?.progressAt(_clock.elapsedMilliseconds);
    final started =
        _race.phase != RacePhase.waiting && _race.phase != RacePhase.countdown;
    return SizedBox(
      height: 250,
      child: RaceArena(
        distance: _distance,
        positions: const {},
        running: started && !_over,
        hudLabel: 'SOLO RUN',
        racers: [
          ArenaRacer(
            id: 'you',
            name: 'YOU',
            color: BmColors.gold,
            progress: me.progress,
            speed: me.speed,
            finished: me.finished,
            isPlayer: true,
          ),
          if (ghostProgress != null)
            ArenaRacer(
              id: 'ghost',
              name: 'BEST',
              color: BmColors.cyan.withValues(alpha: 0.55),
              progress: ghostProgress.round(),
              speed: SpeedStatus.cruising,
              finished: ghostProgress >= _distance,
            ),
        ],
      ),
    );
  }

  Widget _questionArea() {
    if (_race.phase == RacePhase.waiting ||
        _race.phase == RacePhase.countdown) {
      return RaceCountdown(secondsLeft: _countLeft);
    }
    if (_race.phase == RacePhase.racing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text('Next question...', style: BmText.body(14)),
      );
    }

    final question = _question;
    final revealed = _race.phase == RacePhase.answerSubmitted;
    final elapsed = _clock.elapsedMilliseconds - _questionOpenedMs;
    final window = widget.config.questionWindowMs;
    final secondsLeft =
        revealed ? 0 : ((window - elapsed) / 1000).ceil().clamp(0, 99);
    final remaining =
        revealed ? 0.0 : ((window - elapsed) / window).clamp(0.0, 1.0);
    return BmPanel(
      child: Column(
        children: [
          Text(
            revealed
                ? 'Answer: ${question.options[question.correctIndex]}'
                : '${question.category} · ${secondsLeft}s',
            style: BmText.body(12),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: LinearProgressIndicator(
                value: remaining,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(
                  !revealed && secondsLeft <= 3
                      ? Colors.redAccent
                      : BmColors.gold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            question.text,
            textAlign: TextAlign.center,
            style: BmText.title(18),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < question.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AnswerTile(
                letter: 'ABCD'[i],
                text: question.options[i],
                selected: _selected == i,
                correct: revealed && i == question.correctIndex,
                wrong: revealed && _selected == i && i != question.correctIndex,
                enabled: !revealed && _selected == null,
                onTap: () => _pick(i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _results() {
    final ghost = _ghost;
    final finish = _finishMs;
    final delta = _deltaMs;
    return Column(
      children: [
        Text('TIME TRIAL', style: BmText.display(22, color: BmColors.gold)),
        const SizedBox(height: 12),
        BmPanel(
          child: Column(
            children: [
              Text(
                finish == null ? 'DID NOT FINISH' : formatRaceTime(finish),
                style: BmText.display(
                  finish == null ? 22 : 44,
                  color: finish == null ? BmColors.muted : BmColors.gold,
                ),
              ),
              if (_newBest) ...[
                const SizedBox(height: 6),
                Text(
                  'NEW BEST',
                  style: BmText.display(14, color: BmColors.green),
                ),
              ],
              if (delta != null && !_newBest) ...[
                const SizedBox(height: 6),
                Text(
                  '${formatRaceDelta(delta)} vs best',
                  style: BmText.body(
                    13,
                    color: delta < 0 ? BmColors.green : Colors.redAccent,
                  ),
                ),
              ],
              if (ghost != null) ...[
                const SizedBox(height: 6),
                Text(
                  'BEST ${formatRaceTime(ghost.elapsedMs)}',
                  style: BmText.body(12, color: BmColors.muted),
                ),
              ],
            ],
          ),
        ),
        const Spacer(),
        BmButton(
          label: 'RACE AGAIN',
          icon: Icons.replay_rounded,
          style: BmButtonStyle.cyan,
          onPressed: _restart,
        ),
        const SizedBox(height: 8),
        BmButton(
          label: 'BACK TO LOBBY',
          icon: Icons.arrow_back_rounded,
          style: BmButtonStyle.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
