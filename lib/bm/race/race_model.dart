/// Turbo Trivia Race: deterministic race-state model.
///
/// Pure Dart with no UI or network code. Every transition returns a new
/// [RaceModel], so results can be tested and later confirmed by a server.
library;

/// Tunable race values. Defaults follow the Turbo Trivia Race design brief.
class RaceConfig {
  const RaceConfig({
    this.distance = 100,
    this.correctGain = 10,
    this.fastCorrectGain = 15,
    this.fastThresholdMs = 3000,
    this.wrongPenalty = 5,
    this.timeoutPenalty = 3,
    this.dangerZoneMax = 10,
    this.questionWindowMs = 8000,
    this.countdownSeconds = 3,
    this.dangerGraceQuestions = 1,
    this.maxQuestions = 30,
    this.dangerFreeQuestions = 0,
  });

  /// Progress units needed to finish.
  final int distance;

  /// Progress gained for a correct answer.
  final int correctGain;

  /// Progress gained for a correct answer given within [fastThresholdMs].
  final int fastCorrectGain;

  /// Response time that counts as a fast correct answer.
  final int fastThresholdMs;

  /// Progress lost for a wrong answer (never drops below zero).
  final int wrongPenalty;

  /// Progress lost when the question window runs out.
  final int timeoutPenalty;

  /// Progress at or below this value places a racer in the danger zone.
  final int dangerZoneMax;

  /// Time allowed to answer each question.
  final int questionWindowMs;

  /// Countdown length before the race starts.
  final int countdownSeconds;

  /// Question cycles a racer may stay in the danger zone after the warning
  /// before being eliminated.
  final int dangerGraceQuestions;

  /// Question cap that ends the race if no one has finished, so it cannot run
  /// forever.
  final int maxQuestions;

  /// Opening questions during which the danger zone is not judged. Every
  /// racer starts on the grid at 0, inside the zone, so without a safe start
  /// most of the field is knocked out before the race has begun.
  final int dangerFreeQuestions;
}

/// The Turbo Trivia Race rules the game ships with.
const kTurboRaceConfig = RaceConfig(dangerFreeQuestions: 3);

/// Phases of a race, from lobby to results.
enum RacePhase {
  waiting,
  countdown,
  racing,
  questionActive,
  answerSubmitted,
  results,
}

/// A racer's running speed, shown beside their lane during the race.
enum SpeedStatus {
  stopped,
  cruising,
  fast;

  String get label => switch (this) {
        SpeedStatus.stopped => 'STOPPED',
        SpeedStatus.cruising => 'CRUISING',
        SpeedStatus.fast => 'FAST',
      };
}

/// One contestant's confirmed race state.
class RacerProgress {
  const RacerProgress({
    required this.id,
    this.progress = 0,
    this.finishedAtMs,
    this.eliminated = false,
    this.dangerStreak = 0,
    this.speed = SpeedStatus.stopped,
  });

  final String id;
  final int progress;

  /// Race clock time when the racer reached the finish, or null.
  final int? finishedAtMs;
  final bool eliminated;

  /// Consecutive resolved questions this racer ended in the danger zone.
  final int dangerStreak;

  /// Speed from the most recent resolved answer.
  final SpeedStatus speed;

  bool get finished => finishedAtMs != null;

  RacerProgress copyWith({
    int? progress,
    int? finishedAtMs,
    bool? eliminated,
    int? dangerStreak,
    SpeedStatus? speed,
  }) {
    return RacerProgress(
      id: id,
      progress: progress ?? this.progress,
      finishedAtMs: finishedAtMs ?? this.finishedAtMs,
      eliminated: eliminated ?? this.eliminated,
      dangerStreak: dangerStreak ?? this.dangerStreak,
      speed: speed ?? this.speed,
    );
  }
}

/// Immutable race state. Each method returns the next state.
class RaceModel {
  RaceModel({
    required this.config,
    required List<RacerProgress> racers,
    this.phase = RacePhase.waiting,
    this.questionsAsked = 0,
  }) : racers = List.unmodifiable(racers);

  final RaceConfig config;
  final List<RacerProgress> racers;
  final RacePhase phase;

  /// Questions resolved so far, checked against [RaceConfig.maxQuestions].
  final int questionsAsked;

  /// Starts a fresh countdown for a waiting lobby.
  RaceModel startCountdown() {
    if (phase != RacePhase.waiting) return this;
    return _copy(phase: RacePhase.countdown);
  }

  /// Moves from countdown to racing.
  RaceModel go() {
    if (phase != RacePhase.countdown) return this;
    return _copy(phase: RacePhase.racing);
  }

  /// Opens a question window while the race is running.
  RaceModel openQuestion() {
    if (phase != RacePhase.racing) return this;
    return _copy(phase: RacePhase.questionActive);
  }

  /// Applies one racer's answer. [correct] is the server's judgement.
  RaceModel applyAnswer({
    required String racerId,
    required bool correct,
    required int responseMs,
    required int atMs,
  }) {
    if (phase != RacePhase.questionActive) return this;
    final racer = _find(racerId);
    if (racer == null || racer.eliminated || racer.finished) return this;

    final fast = responseMs <= config.fastThresholdMs;
    final delta = correct
        ? (fast ? config.fastCorrectGain : config.correctGain)
        : -config.wrongPenalty;
    return _update(
      racer,
      delta,
      atMs,
      speed: correct
          ? (fast ? SpeedStatus.fast : SpeedStatus.cruising)
          : SpeedStatus.stopped,
    );
  }

  /// Applies the timeout penalty to every racer who did not answer.
  RaceModel applyTimeout({
    required Set<String> answeredIds,
    required int atMs,
  }) {
    if (phase != RacePhase.questionActive) return this;
    var next = this;
    for (final racer in racers) {
      if (answeredIds.contains(racer.id)) continue;
      if (racer.eliminated || racer.finished) continue;
      next = next._update(
        next._find(racer.id)!,
        -config.timeoutPenalty,
        atMs,
        speed: SpeedStatus.stopped,
      );
    }
    return next._copy(phase: RacePhase.answerSubmitted);
  }

  /// Resolves the question: judges the danger zone, eliminates racers whose
  /// grace period has run out, and returns to racing. Ends the race when the
  /// question cap is reached or no contestant can still move.
  RaceModel resolveQuestion() {
    if (phase != RacePhase.answerSubmitted &&
        phase != RacePhase.questionActive) {
      return this;
    }
    final next = _copy(
      racers: [for (final r in racers) _judgeDanger(r)],
      phase: RacePhase.racing,
      questionsAsked: questionsAsked + 1,
    );
    final anyoneActive = next.racers.any((r) => !r.finished && !r.eliminated);
    if (!anyoneActive || next.questionsAsked >= config.maxQuestions) {
      return next.finish();
    }
    return next;
  }

  RacerProgress _judgeDanger(RacerProgress racer) {
    if (racer.eliminated || racer.finished) return racer;
    if (questionsAsked < config.dangerFreeQuestions) {
      return racer.copyWith(dangerStreak: 0);
    }
    if (racer.progress > config.dangerZoneMax) {
      return racer.copyWith(dangerStreak: 0);
    }
    final streak = racer.dangerStreak + 1;
    return racer.copyWith(
      dangerStreak: streak,
      eliminated: streak > config.dangerGraceQuestions,
    );
  }

  /// Ends the race once no contestant can still move forward.
  RaceModel finishIfDone() {
    if (phase == RacePhase.results) return this;
    final stillRacing = racers.any((r) => !r.finished && !r.eliminated);
    if (stillRacing) return this;
    return _copy(phase: RacePhase.results);
  }

  /// Ends the race at once, used when the first racer reaches the finish.
  RaceModel finish() {
    if (phase == RacePhase.results) return this;
    return _copy(phase: RacePhase.results);
  }

  /// Whether this racer is in the danger zone.
  bool inDangerZone(String racerId) {
    final racer = _find(racerId);
    if (racer == null || racer.eliminated || racer.finished) return false;
    if (questionsAsked < config.dangerFreeQuestions) return false;
    return racer.progress <= config.dangerZoneMax;
  }

  /// Race position per racer, numbered from 1 in [rankings] order.
  Map<String, int> get positions {
    final order = rankings;
    return {
      for (var i = 0; i < order.length; i++) order[i].id: i + 1,
    };
  }

  /// 1-based race position, or the field size for an unknown racer.
  int positionOf(String racerId) => positions[racerId] ?? racers.length;

  /// Whether this racer is out but the race is still running, so they watch.
  bool spectating(String racerId) {
    final racer = _find(racerId);
    if (racer == null || !racer.eliminated) return false;
    return phase != RacePhase.results;
  }

  /// Race rankings: finished racers first (earliest finish first), then the
  /// rest by progress. Ties break on id, so ordering is deterministic.
  List<RacerProgress> get rankings {
    final sorted = [...racers];
    sorted.sort((a, b) {
      if (a.finished != b.finished) return a.finished ? -1 : 1;
      if (a.finished) {
        final byTime = a.finishedAtMs!.compareTo(b.finishedAtMs!);
        if (byTime != 0) return byTime;
      } else if (a.eliminated != b.eliminated) {
        return a.eliminated ? 1 : -1;
      } else {
        final byProgress = b.progress.compareTo(a.progress);
        if (byProgress != 0) return byProgress;
      }
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  RacerProgress? _find(String id) {
    for (final racer in racers) {
      if (racer.id == id) return racer;
    }
    return null;
  }

  RaceModel _update(
    RacerProgress racer,
    int delta,
    int atMs, {
    required SpeedStatus speed,
  }) {
    final next = (racer.progress + delta).clamp(0, config.distance).toInt();
    final finished = next >= config.distance;
    final updated = racer.copyWith(
      progress: next,
      finishedAtMs: finished && !racer.finished ? atMs : null,
      speed: speed,
    );
    return _copy(
      racers: [
        for (final r in racers) r.id == racer.id ? updated : r,
      ],
    );
  }

  RaceModel _copy({
    List<RacerProgress>? racers,
    RacePhase? phase,
    int? questionsAsked,
  }) {
    return RaceModel(
      config: config,
      racers: racers ?? this.racers,
      phase: phase ?? this.phase,
      questionsAsked: questionsAsked ?? this.questionsAsked,
    );
  }
}
