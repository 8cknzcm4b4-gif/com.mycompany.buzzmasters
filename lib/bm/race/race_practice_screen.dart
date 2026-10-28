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
import 'elimination_flash.dart';
import 'finish_confetti.dart';
import 'race_model.dart';
import 'race_sound.dart';
import 'treadmill_lane.dart';

const _humanId = 'you';
const _racerNames = <String, String>{
  _humanId: 'You',
  'alex': 'Alex',
  'sophie': 'Sophie',
  'jordan': 'Jordan',
  'emma': 'Emma',
  'liam': 'Liam',
};

/// Podium colours from the Buzz Masters studio reference.
const _racerColors = <String, Color>{
  _humanId: BmColors.gold,
  'alex': BmColors.cyan,
  'sophie': Color(0xFFFF5CA8),
  'jordan': BmColors.green,
  'emma': Color(0xFFFFA53D),
  'liam': Color(0xFF9C6CFF),
};

/// Offline Turbo Trivia Race: one player against five computer racers.
/// Race rules live in [RaceModel]; this screen runs the clock and the
/// computer racers' answers.
class RacePracticeScreen extends StatefulWidget {
  const RacePracticeScreen({super.key, this.random});

  /// Injected by tests; defaults to a fresh random source.
  final Random? random;

  @override
  State<RacePracticeScreen> createState() => _RacePracticeScreenState();
}

class _RacePracticeScreenState extends State<RacePracticeScreen> {
  static const _config = RaceConfig();
  static const _botCorrectChance = 0.6;
  static const _botMinDelayMs = 1500;
  static const _botDelaySpreadMs = 4500;
  static const _revealMs = 1500;

  late final Random _rng = widget.random ?? Random();
  late final List<QuizQuestion> _questions = [...kPracticeQuestions]
    ..shuffle(_rng);
  final Stopwatch _clock = Stopwatch();
  final Set<String> _answered = {};
  final List<Timer> _botTimers = [];
  Timer? _countdownTimer;
  Timer? _windowTimer;
  Timer? _revealTimer;
  Timer? _refresh;
  Timer? _outTimer;

  /// Racers eliminated by the last resolved question, highlighted briefly.
  Set<String> _justEliminated = <String>{};

  late RaceModel _race = RaceModel(
    config: _config,
    racers: [for (final id in _racerNames.keys) RacerProgress(id: id)],
  );
  int _countLeft = _config.countdownSeconds;
  int _questionIndex = 0;
  int _questionOpenedMs = 0;
  int? _selected;

  /// Guards against opening settings twice while the route is in flight.
  bool _settingsOpen = false;

  QuizQuestion get _question => _questions[_questionIndex % _questions.length];

  @override
  void initState() {
    super.initState();
    unawaited(BmAudioSettings.ensureLoaded());
    _refresh = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
    _race = _race.startCountdown();
    _startCountdown();
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

  @override
  void dispose() {
    _clock.stop();
    _countdownTimer?.cancel();
    _windowTimer?.cancel();
    _revealTimer?.cancel();
    _refresh?.cancel();
    _outTimer?.cancel();
    _cancelBots();
    super.dispose();
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
    // First racer to the finish line ends the race for everyone.
    if (_race.phase == RacePhase.results ||
        _race.racers.any((r) => r.finished) ||
        _activeIds().isEmpty) {
      _endRace();
      return;
    }
    _questionOpenedMs = _clock.elapsedMilliseconds;
    setState(() {
      _race = _race.openQuestion();
      _answered.clear();
      _selected = null;
    });
    _scheduleBotAnswers();
    _windowTimer = Timer(
      Duration(milliseconds: _config.questionWindowMs),
      _closeWindow,
    );
  }

  /// Queues an answer for every computer racer still in the question.
  void _scheduleBotAnswers() {
    for (final racer in _race.racers) {
      if (racer.id == _humanId || racer.finished) continue;
      if (_answered.contains(racer.id)) continue;
      final id = racer.id;
      final delay = _botMinDelayMs + _rng.nextInt(_botDelaySpreadMs);
      _botTimers.add(Timer(Duration(milliseconds: delay), () {
        _answer(id,
            correct: _rng.nextDouble() < _botCorrectChance,
            responseMs: delay);
      }));
    }
  }

  /// Opens settings with the race frozen, so changing sound or haptics can
  /// never cost the player a question. Everything that was running is
  /// restarted with its remaining time once the settings screen closes.
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
    _cancelBots();
    _clock.stop();
    final pausedAt = DateTime.now().millisecondsSinceEpoch;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BmSettingsScreen()),
    );
    if (!mounted) return;
    _settingsOpen = false;

    // The paused stretch must not count towards the player's response time.
    if (clockWasRunning) {
      _questionOpenedMs +=
          DateTime.now().millisecondsSinceEpoch - pausedAt;
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
      _scheduleBotAnswers();
    } else if (wasCountingDown) {
      _startCountdown();
    }
  }

  /// Time left on the current question window, in milliseconds.
  int get _windowRemainingMs {
    final used = _clock.elapsedMilliseconds - _questionOpenedMs;
    final left = _config.questionWindowMs - used;
    return left < 0 ? 0 : left;
  }

  List<String> _activeIds() => [
        for (final r in _race.racers)
          if (!r.finished && !r.eliminated) r.id,
      ];

  void _answer(String id, {required bool correct, required int responseMs}) {
    if (!mounted ||
        _race.phase != RacePhase.questionActive ||
        _answered.contains(id)) {
      return;
    }
    setState(() {
      _race = _race.applyAnswer(
        racerId: id,
        correct: correct,
        responseMs: responseMs,
        atMs: _clock.elapsedMilliseconds,
      );
      _answered.add(id);
    });
    if (_activeIds().every(_answered.contains)) _closeWindow();
  }

  void _pick(int index) {
    if (_selected != null ||
        _race.phase != RacePhase.questionActive ||
        _race.spectating(_humanId)) {
      return;
    }
    final correct = index == _question.correctIndex;
    setState(() => _selected = index);
    unawaited(correct ? RaceSound.answerCorrect() : RaceSound.answerWrong());
    _answer(
      _humanId,
      correct: correct,
      responseMs: _clock.elapsedMilliseconds - _questionOpenedMs,
    );
  }

  void _closeWindow() {
    if (!mounted || _race.phase != RacePhase.questionActive) return;
    _windowTimer?.cancel();
    _cancelBots();
    setState(() {
      _race = _race.applyTimeout(
        answeredIds: _answered,
        atMs: _clock.elapsedMilliseconds,
      );
    });
    _revealTimer = Timer(const Duration(milliseconds: _revealMs), () {
      _resolveAndContinue();
    });
  }

  void _resolveAndContinue() {
    if (!mounted) return;
    final before = _eliminatedIds();
    final resolved = _race.resolveQuestion();
    final out = {
      for (final racer in resolved.racers)
        if (racer.eliminated && !before.contains(racer.id)) racer.id,
    };
    setState(() {
      _race = resolved;
      _questionIndex++;
      _justEliminated = out;
    });
    if (out.isNotEmpty) {
      unawaited(RaceSound.eliminated());
      _outTimer?.cancel();
      _outTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _justEliminated = <String>{});
      });
    }
    _nextQuestion();
  }

  void _endRace() {
    _clock.stop();
    _countdownTimer?.cancel();
    _windowTimer?.cancel();
    _revealTimer?.cancel();
    _outTimer?.cancel();
    _cancelBots();
    unawaited(RaceSound.finish());
    setState(() {
      _race = _race.finish();
      _justEliminated = <String>{};
    });
  }

  Set<String> _eliminatedIds() => {
        for (final racer in _race.racers)
          if (racer.eliminated) racer.id,
      };

  void _cancelBots() {
    for (final timer in _botTimers) {
      timer.cancel();
    }
    _botTimers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final finished = _race.phase == RacePhase.results;
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  'PRACTICE RACE',
                  textAlign: TextAlign.center,
                  style: BmText.display(18, color: BmColors.gold),
                ),
              ),
              SizedBox(
                width: 48,
                child: Center(
                  child: BmIconButton(
                    icon: Icons.settings_rounded,
                    color: BmColors.gold,
                    onPressed: _openSettings,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: finished
                ? Stack(
                    children: [
                      _results(),
                      const Positioned.fill(child: FinishConfetti()),
                    ],
                  )
                : SingleChildScrollView(child: _raceView()),
          ),
        ],
      ),
    );
  }

  Widget _raceView() {
    // The belt scrolls with the race clock, so it moves while questions run.
    final beltOffset = _clock.elapsedMilliseconds / 40;
    final positions = _race.positions;
    // Grid positions are meaningless until the countdown ends.
    final showPositions = _race.phase != RacePhase.waiting &&
        _race.phase != RacePhase.countdown;
    Widget lane(RacerProgress racer) => TreadmillLane(
          name: _racerNames[racer.id] ?? racer.id,
          position: showPositions ? positions[racer.id] ?? 0 : 0,
          speed: racer.speed,
          progress: racer.progress,
          distance: _config.distance,
          beltOffset: beltOffset,
          laneColor: _racerColors[racer.id] ?? BmColors.cyan,
          finished: racer.finished,
          eliminated: racer.eliminated,
          warning: _race.inDangerZone(racer.id),
          nearFinish: racer.progress >= _config.distance * 0.75,
        );
    return Column(
      children: [
        for (final racer in _race.racers)
          if (_justEliminated.contains(racer.id))
            EliminationFlash(
              key: ValueKey<String>('out-${racer.id}'),
              child: lane(racer),
            )
          else
            lane(racer),
        const SizedBox(height: 12),
        _questionArea(),
      ],
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
    if (_race.spectating(_humanId)) {
      return BmPanel(
        child: Column(
          children: [
            const Icon(
              Icons.visibility_rounded,
              color: BmColors.cyan,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text('SPECTATING', style: BmText.display(16, color: BmColors.cyan)),
            const SizedBox(height: 6),
            Text(
              'You are OUT. The race continues without you.',
              textAlign: TextAlign.center,
              style: BmText.body(12),
            ),
          ],
        ),
      );
    }

    final question = _question;
    final revealed = _race.phase == RacePhase.answerSubmitted;
    final secondsLeft = revealed
        ? 0
        : ((_config.questionWindowMs -
                    (_clock.elapsedMilliseconds - _questionOpenedMs)) /
                1000)
            .ceil()
            .clamp(0, 99);
    final remaining = revealed
        ? 0.0
        : ((_config.questionWindowMs -
                    (_clock.elapsedMilliseconds - _questionOpenedMs)) /
                _config.questionWindowMs)
            .clamp(0.0, 1.0);
    return BmPanel(
      child: Column(
        children: [
          Text(
            revealed
                ? 'Answer: ${question.options[question.correctIndex]}'
                : '${question.category} · ${secondsLeft}s',
            style: BmText.body(12),
          ),
          if (_justEliminated.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'OUT: ${_justEliminated.map((id) => _racerNames[id] ?? id).join(' · ')}',
                style: BmText.label(10, color: Colors.redAccent),
              ),
            ),
          const SizedBox(height: 6),
          _TimerBar(
            fraction: remaining,
            urgent: !revealed && secondsLeft <= 3,
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
    final order = _race.rankings;
    return Column(
      children: [
        Text('RESULTS', style: BmText.display(22, color: BmColors.gold)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              for (var i = 0; i < order.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: BmPanel(
                    child: Row(
                      children: [
                        Text(
                          order[i].finished ? 'P${i + 1}' : '${i + 1}',
                          style: BmText.display(16, color: BmColors.gold),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _racerNames[order[i].id] ?? order[i].id,
                            style: BmText.title(16),
                          ),
                        ),
                        if (order[i].eliminated)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              'OUT',
                              style: BmText.label(10, color: BmColors.muted),
                            ),
                          ),
                        Text(
                          order[i].finished
                              ? 'FINISHED'
                              : '${order[i].progress} / ${_config.distance}',
                          style: BmText.body(13),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        BmButton(
          label: 'BACK TO LOBBY',
          icon: Icons.arrow_back_rounded,
          style: BmButtonStyle.cyan,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// The question countdown, drawn as a bar that empties with the clock.
class _TimerBar extends StatelessWidget {
  const _TimerBar({required this.fraction, required this.urgent});

  final double fraction;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 5,
        child: LinearProgressIndicator(
          value: fraction,
          backgroundColor: Colors.white24,
          valueColor: AlwaysStoppedAnimation<Color>(
            urgent ? Colors.redAccent : BmColors.gold,
          ),
        ),
      ),
    );
  }
}
