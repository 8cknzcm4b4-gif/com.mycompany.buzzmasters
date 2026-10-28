import 'dart:async';
import 'dart:math';

import '../../game/practice_match.dart';
import '../race_model.dart';
import 'race_protocol.dart';

/// Authoritative Turbo Trivia Race server.
///
/// Owns the only copy of race state that counts. It judges every answer,
/// applies movement, runs the question deadlines and ends the race. Clients
/// receive snapshots and notices; they cannot move a racer.
///
/// Time comes from an injectable clock so tests can drive deadlines exactly.
class RaceServer {
  RaceServer({
    required this.matchId,
    required List<String> racerIds,
    required List<QuizQuestion> questions,
    this.config = const RaceConfig(),
    this.betweenQuestionsMs = 1500,
    this.shuffleOptions = true,
    int Function()? clock,
    Random? random,
  })  : _clock = clock ?? _wallClock,
        roster = List<String>.unmodifiable(racerIds) {
    final rng = random ?? Random();
    _questions = shuffleOptions
        ? _shuffleOptions(questions, rng)
        : List<QuizQuestion>.of(questions);
    _model = RaceModel(
      config: config,
      racers: [for (final id in roster) RacerProgress(id: id)],
    );
  }

  final String matchId;
  final List<String> roster;
  final RaceConfig config;

  /// Pause between resolving a question and opening the next one.
  final int betweenQuestionsMs;
  final bool shuffleOptions;

  final int Function() _clock;
  late final List<QuizQuestion> _questions;
  late RaceModel _model;

  final Set<String> _joined = <String>{};
  final Set<String> _answered = <String>{};
  final StreamController<RaceSnapshot> _snapshots =
      StreamController<RaceSnapshot>.broadcast();

  bool _started = false;
  int? _questionIndex;
  int? _deadlineMs;
  int _questionOpenedMs = 0;
  int? _nextQuestionAt;

  /// Racers eliminated by the most recently resolved question.
  Set<String> lastEliminated = <String>{};

  /// Broadcast of every state change, for connected clients.
  Stream<RaceSnapshot> get snapshots => _snapshots.stream;

  /// The rules engine, exposed read-only for tests and state logging.
  RaceModel get state => _model;

  bool get started => _started;
  Set<String> get joinedRacers => Set<String>.unmodifiable(_joined);

  /// Adds a racer from the roster. Unknown ids are refused.
  bool join(String racerId) {
    if (!roster.contains(racerId)) return false;
    if (!_joined.add(racerId)) return false;
    _emit();
    return true;
  }

  /// Starts the countdown. Safe to call once.
  void start() {
    if (_started) return;
    _started = true;
    _model = _model.startCountdown();
    _deadlineMs = _clock() + config.countdownSeconds * 1000;
    _emit();
  }

  /// Handles one client command and returns the notice for that racer.
  RaceNotice handle(RaceCommand command) {
    if (command is SubmitAnswer) return _submit(command);
    if (command is JoinRace) {
      final accepted = join(command.racerId);
      return RaceNotice(
        racerId: command.racerId,
        status: accepted
            ? RaceAnswerStatus.accepted
            : RaceAnswerStatus.rejectedUnknownRacer,
      );
    }
    if (command is LeaveRace) {
      final removed = _joined.remove(command.racerId);
      if (removed) _emit();
      return RaceNotice(
        racerId: command.racerId,
        status: RaceAnswerStatus.accepted,
      );
    }
    return RaceNotice(
      racerId: command.racerId,
      status: RaceAnswerStatus.rejectedOutOfPhase,
    );
  }

  RaceNotice _submit(SubmitAnswer command) {
    final now = _clock();
    final racerId = command.racerId;
    RaceNotice reject(RaceAnswerStatus status) =>
        RaceNotice(racerId: racerId, status: status);

    final racer = _racer(racerId);
    if (!_joined.contains(racerId) || racer == null) {
      return reject(RaceAnswerStatus.rejectedUnknownRacer);
    }
    final questionIndex = _questionIndex;
    if (_model.phase != RacePhase.questionActive || questionIndex == null) {
      return reject(RaceAnswerStatus.rejectedOutOfPhase);
    }
    if (command.questionIndex != questionIndex) {
      return reject(RaceAnswerStatus.rejectedOutOfPhase);
    }
    if (racer.eliminated) return reject(RaceAnswerStatus.rejectedEliminated);
    if (racer.finished) return reject(RaceAnswerStatus.rejectedOutOfPhase);
    final deadline = _deadlineMs;
    if (deadline == null || now > deadline) {
      return reject(RaceAnswerStatus.rejectedLate);
    }
    if (_answered.contains(racerId)) {
      return reject(RaceAnswerStatus.rejectedDuplicate);
    }
    final question = _questions[questionIndex];
    if (command.optionIndex < 0 ||
        command.optionIndex >= question.options.length) {
      return reject(RaceAnswerStatus.rejectedInvalidOption);
    }

    _answered.add(racerId);
    final correct = command.optionIndex == question.correctIndex;
    // Response time is measured by the server, never sent by the client.
    _model = _model.applyAnswer(
      racerId: racerId,
      correct: correct,
      responseMs: now - _questionOpenedMs,
      atMs: now,
    );
    final progress = _racer(racerId)!.progress;

    if (_model.racers.any((r) => r.finished)) {
      _finishNow();
    } else if (_activeIds().every(_answered.contains)) {
      _closeQuestion(now);
    }
    _emit();
    return RaceNotice(
      racerId: racerId,
      status: RaceAnswerStatus.accepted,
      correct: correct,
      progress: progress,
    );
  }

  /// Advances server timers: start, question deadlines and the pause between
  /// questions. Call this on a fixed tick from the host.
  void tick() {
    final now = _clock();
    var changed = false;
    final deadline = _deadlineMs;
    if (_model.phase == RacePhase.countdown &&
        deadline != null &&
        now >= deadline) {
      _model = _model.go();
      _openQuestion(now);
      changed = true;
    } else if (_model.phase == RacePhase.questionActive &&
        deadline != null &&
        now >= deadline) {
      _closeQuestion(now);
      changed = true;
    } else if (_model.phase == RacePhase.racing &&
        _nextQuestionAt != null &&
        now >= _nextQuestionAt!) {
      _openQuestion(now);
      changed = true;
    }
    if (changed) _emit();
  }

  void _openQuestion(int now) {
    final index = _model.questionsAsked;
    if (index >= _questions.length) {
      _finishNow();
      return;
    }
    _questionIndex = index;
    _questionOpenedMs = now;
    _deadlineMs = now + config.questionWindowMs;
    _nextQuestionAt = null;
    _answered.clear();
    _model = _model.openQuestion();
  }

  void _closeQuestion(int now) {
    _model = _model.applyTimeout(answeredIds: _answered, atMs: now);
    final before = {
      for (final racer in _model.racers)
        if (racer.eliminated) racer.id,
    };
    _model = _model.resolveQuestion();
    lastEliminated = {
      for (final racer in _model.racers)
        if (racer.eliminated && !before.contains(racer.id)) racer.id,
    };
    _answered.clear();
    _deadlineMs = null;
    if (_model.phase == RacePhase.results) return;
    if (_model.racers.any((r) => r.finished)) {
      _finishNow();
      return;
    }
    _nextQuestionAt = now + betweenQuestionsMs;
  }

  void _finishNow() {
    _model = _model.finish();
    _deadlineMs = null;
    _nextQuestionAt = null;
  }

  /// Current authoritative state, safe to send to any client.
  RaceSnapshot snapshot() {
    final index = _questionIndex;
    final question = _model.phase == RacePhase.questionActive && index != null
        ? _questionView(index, _deadlineMs ?? _clock())
        : null;
    final positions = _model.positions;
    return RaceSnapshot(
      matchId: matchId,
      phase: _model.phase,
      questionsAsked: _model.questionsAsked,
      question: question,
      racers: [
        for (final racer in _model.racers)
          RacerState(
            id: racer.id,
            position: positions[racer.id] ?? 0,
            progress: racer.progress,
            speed: racer.speed,
            finished: racer.finished,
            eliminated: racer.eliminated,
            inDanger: _model.inDangerZone(racer.id),
            finishedAtMs: racer.finishedAtMs,
          ),
      ],
      ranking: [for (final racer in _model.rankings) racer.id],
      serverTimeMs: _clock(),
    );
  }

  QuestionView _questionView(int index, int deadlineMs) {
    final question = _questions[index];
    return QuestionView(
      index: index,
      id: question.id,
      category: question.category,
      text: question.text,
      options: List<String>.unmodifiable(question.options),
      deadlineMs: deadlineMs,
    );
  }

  Future<void> dispose() async {
    _deadlineMs = null;
    _nextQuestionAt = null;
    await _snapshots.close();
  }

  RacerProgress? _racer(String id) {
    for (final racer in _model.racers) {
      if (racer.id == id) return racer;
    }
    return null;
  }

  Set<String> _activeIds() => {
        for (final racer in _model.racers)
          if (!racer.finished && !racer.eliminated) racer.id,
      };

  void _emit() {
    if (!_snapshots.isClosed) _snapshots.add(snapshot());
  }

  static List<QuizQuestion> _shuffleOptions(
    List<QuizQuestion> questions,
    Random random,
  ) {
    return [
      for (final question in questions) _shuffleOne(question, random),
    ];
  }

  static QuizQuestion _shuffleOne(QuizQuestion question, Random random) {
    final order = List<int>.generate(question.options.length, (i) => i)
      ..shuffle(random);
    return QuizQuestion(
      id: question.id,
      category: question.category,
      difficulty: question.difficulty,
      text: question.text,
      options: [for (final i in order) question.options[i]],
      correctIndex: order.indexOf(question.correctIndex),
      explanation: question.explanation,
    );
  }

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;
}
