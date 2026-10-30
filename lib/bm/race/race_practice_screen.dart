import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../game/practice_match.dart';
import '../player/player_profile.dart';
import '../screens/settings_screen.dart';
import '../settings/bm_audio_settings.dart';
import '../settings/bm_music.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/race_podium.dart';
import '../widgets/studio_background.dart';
import 'countdown_badge.dart';
import 'finish_confetti.dart';
import 'race_arena.dart';
import 'race_model.dart';
import 'race_sound.dart';

const _humanId = 'you';

/// Computer racers, clearly labelled as CPU in the lobby and results.
const _botNames = <String, String>{
  'alex': 'Alex',
  'sophie': 'Sophie',
  'jordan': 'Jordan',
  'emma': 'Emma',
  'liam': 'Liam',
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
  static const _config = kTurboRaceConfig;
  static const _botCorrectChance = 0.6;
  static const _botMinDelayMs = 1500;
  static const _botDelaySpreadMs = 4500;
  static const _revealMs = 1500;
  static const _finishFlashMs = 1800;

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
    racers: [
      const RacerProgress(id: _humanId),
      for (final id in _botNames.keys) RacerProgress(id: id),
    ],
  );
  int _countLeft = _config.countdownSeconds;
  int _questionIndex = 0;
  int _questionOpenedMs = 0;
  int? _selected;

  /// Guards against opening settings twice while the route is in flight.
  bool _settingsOpen = false;

  /// The player's answers this race, recorded to their profile at the end.
  int _humanCorrect = 0;
  int _humanAnswered = 0;

  /// The finish flash has played and the podium ceremony is showing.
  bool _showPodium = false;
  bool _ended = false;
  Timer? _podiumTimer;

  late final PlayerStats _profile = PlayerProfileStore.current.value;

  late final Map<String, String> _names = {
    _humanId: _profile.name,
    ..._botNames,
  };

  /// The player keeps their profile colour; CPU racers take the rest.
  late final Map<String, Color> _colors = () {
    final rest = [
      for (var i = 0; i < BmColors.seatColors.length; i++)
        if (i != _profile.colorIndex % BmColors.seatColors.length)
          BmColors.seatColors[i],
    ];
    return {
      _humanId: _profile.color,
      for (final (i, id) in _botNames.keys.indexed) id: rest[i % rest.length],
    };
  }();

  QuizQuestion get _question => _questions[_questionIndex % _questions.length];

  @override
  void initState() {
    super.initState();
    unawaited(BmAudioSettings.ensureLoaded());
    // The race has its own cues; menu music resumes when the player leaves.
    unawaited(BmMusic.stop());
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
    _podiumTimer?.cancel();
    _cancelBots();
    unawaited(BmMusic.start());
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
            correct: _rng.nextDouble() < _botCorrectChance, responseMs: delay);
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
    _humanAnswered++;
    if (correct) _humanCorrect++;
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
    if (_ended) return;
    _ended = true;
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
    unawaited(PlayerProfileStore.recordRace(
      placing: _race.positionOf(_humanId),
      correctAnswers: _humanCorrect,
      answeredQuestions: _humanAnswered,
    ));
    _podiumTimer = Timer(const Duration(milliseconds: _finishFlashMs), () {
      if (mounted) setState(() => _showPodium = true);
    });
  }

  void _rematch() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => RacePracticeScreen(random: widget.random),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
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
    final over = _race.phase == RacePhase.results;
    final leader = _race.racers.map((r) => r.progress).fold(0, max);
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      showAudience: false,
      intensity: over ? 1 : 0.3 + 0.7 * leader / _config.distance,
      child: Column(
        children: [
          ArenaHeader(
            title: 'PRACTICE RACE',
            subtitle: 'YOU VS 5 CPU RACERS',
            titleColor: BmColors.gold,
            trailing: BmIconButton(
              icon: Icons.settings_rounded,
              color: BmColors.gold,
              tooltip: 'Settings',
              onPressed: _openSettings,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: _showPodium
                  ? Stack(
                      key: const ValueKey('podium'),
                      children: [
                        _results(),
                        const Positioned.fill(child: FinishConfetti()),
                      ],
                    )
                  : LayoutBuilder(
                      key: const ValueKey('race'),
                      builder: (context, box) {
                        final trackH = (box.maxHeight * 0.46)
                            .clamp(200.0, 380.0)
                            .toDouble();
                        return Column(
                          children: [
                            SizedBox(height: trackH, child: _arena()),
                            const SizedBox(height: 10),
                            Expanded(
                              child: SingleChildScrollView(
                                child: _questionArea(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _arena() {
    final showPositions =
        _race.phase != RacePhase.waiting && _race.phase != RacePhase.countdown;
    final counting = !showPositions;
    return RaceArena(
      distance: _config.distance,
      positions: showPositions ? _race.positions : const {},
      running: _race.phase != RacePhase.results && !counting,
      finished: _race.phase == RacePhase.results,
      hudLabel: counting
          ? 'GRID'
          : 'Q ${min(_questionIndex + 1, _config.maxQuestions)} / ${_config.maxQuestions}',
      overlay: counting ? RaceCountdown(secondsLeft: _countLeft) : null,
      onPlayerOvertake: () => unawaited(RaceSound.overtake()),
      racers: [
        for (final r in _race.racers)
          ArenaRacer(
            id: r.id,
            name: _names[r.id] ?? r.id,
            color: _colors[r.id] ?? BmColors.cyan,
            progress: r.progress,
            speed: r.speed,
            finished: r.finished,
            eliminated: r.eliminated,
            danger: showPositions && _race.inDangerZone(r.id),
            isPlayer: r.id == _humanId,
          ),
      ],
    );
  }

  Widget _questionArea() {
    if (_race.phase == RacePhase.waiting ||
        _race.phase == RacePhase.countdown) {
      return _infoCard(
        icon: Icons.bolt_rounded,
        color: BmColors.cyan,
        title: 'ANSWER FAST TO ACCELERATE',
        body: 'Fast correct +15 · Correct +10 · Wrong −5 · Timeout −3.\n'
            'Stay out of the red danger zone or you are out.',
      );
    }
    if (_race.phase == RacePhase.results) {
      final place = _race.positionOf(_humanId);
      return _infoCard(
        icon: Icons.sports_score_rounded,
        color: BmColors.gold,
        title: place == 1 ? 'YOU TAKE THE CHEQUERED FLAG!' : 'RACE OVER',
        body: 'You finished P$place. Heading to the podium…',
      );
    }
    if (_race.phase == RacePhase.racing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text('NEXT QUESTION…',
              style: BmText.label(13, color: BmColors.cyan)),
        ),
      );
    }
    if (_race.spectating(_humanId)) {
      return _infoCard(
        icon: Icons.visibility_rounded,
        color: BmColors.red,
        title: 'SPECTATING',
        body: 'You are OUT. The race continues without you.',
      );
    }

    final question = _question;
    final revealed = _race.phase == RacePhase.answerSubmitted;
    final usedMs = _clock.elapsedMilliseconds - _questionOpenedMs;
    final leftMs =
        revealed ? 0 : (_config.questionWindowMs - usedMs).clamp(0, 99999);
    final pickedRight = _selected != null && _selected == question.correctIndex;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, a) => SlideTransition(
        position: Tween(begin: const Offset(0.15, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: a, child: child),
      ),
      child: BmPanel(
        key: ValueKey('q$_questionIndex'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        color: revealed
            ? (pickedRight ? BmColors.green : BmColors.violet)
            : BmColors.violet,
        child: Column(
          children: [
            Row(
              children: [
                BmChip(text: question.category, color: BmColors.cyan),
                const SizedBox(width: 6),
                BmChip(text: question.difficulty, color: BmColors.purple),
                const Spacer(),
                TimerRing(
                  secondsLeft: leftMs / 1000,
                  total: _config.questionWindowMs / 1000,
                  size: 46,
                ),
              ],
            ),
            if (_justEliminated.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'OUT: ${_justEliminated.map((id) => _names[id] ?? id).join(' · ')}',
                  style: BmText.label(10, color: BmColors.red),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              question.text,
              textAlign: TextAlign.center,
              style: BmText.title(18).copyWith(height: 1.3),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 20,
              child: revealed
                  ? Text(
                      'Answer: ${question.options[question.correctIndex]}',
                      style: BmText.body(12,
                          color: pickedRight ? BmColors.green : BmColors.gold,
                          weight: FontWeight.w600),
                    )
                  : null,
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < question.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AnswerTile(
                  letter: 'ABCD'[i],
                  text: question.options[i],
                  selected: _selected == i,
                  correct: revealed && i == question.correctIndex,
                  wrong: _selected == i && i != question.correctIndex,
                  enabled: !revealed && _selected == null,
                  onTap: () => _pick(i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return BmPanel(
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
  }

  Widget _results() {
    final order = _race.rankings;
    final place = _race.positionOf(_humanId);
    String detail(RacerProgress r) => r.finished
        ? 'FINISHED'
        : r.eliminated
            ? 'OUT'
            : '${r.progress} / ${_config.distance}';
    return Column(
      children: [
        Text('RESULTS', style: BmText.display(26, color: BmColors.gold)),
        Text(
          place == 1 ? 'YOU WIN THE RACE!' : 'YOU FINISHED P$place',
          style: BmText.label(11, color: Colors.white),
        ),
        const SizedBox(height: 4),
        RacePodium(
          height: 220,
          entries: [
            for (final r in order.take(3))
              PodiumEntry(
                name: _names[r.id] ?? r.id,
                color: _colors[r.id] ?? BmColors.cyan,
                detail: detail(r),
                isPlayer: r.id == _humanId,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (var i = 3; i < order.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: BmPanel(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    color: order[i].id == _humanId
                        ? BmColors.gold
                        : BmColors.panelEdge,
                    child: Row(
                      children: [
                        Text('P${i + 1}',
                            style: BmText.display(15, color: BmColors.muted)),
                        const SizedBox(width: 12),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _colors[order[i].id],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_names[order[i].id] ?? order[i].id,
                              style: BmText.title(14)),
                        ),
                        Text(detail(order[i]),
                            style: BmText.label(10,
                                color: order[i].eliminated
                                    ? BmColors.red
                                    : BmColors.muted)),
                      ],
                    ),
                  ),
                ),
              BmPanel(
                color: BmColors.cyan,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _stat('PLACE', 'P$place'),
                    _stat('CORRECT', '$_humanCorrect/$_humanAnswered'),
                    _stat('QUESTIONS', '${_race.questionsAsked}'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        BmButton(
          label: 'RACE AGAIN',
          icon: Icons.replay_rounded,
          height: 52,
          onPressed: _rematch,
        ),
        const SizedBox(height: 8),
        BmButton(
          label: 'BACK TO LOBBY',
          icon: Icons.arrow_back_rounded,
          style: BmButtonStyle.outline,
          height: 46,
          onPressed: () => Navigator.of(context).pop(),
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
