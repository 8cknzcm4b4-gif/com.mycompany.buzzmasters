/// Wire protocol for the authoritative race server.
///
/// Clients send intents only: no progress, scores or timestamps are trusted
/// from a client. The server answers with snapshots and notices.
library;

import '../race_model.dart';

/// A command a client may send. Every command names the racer it acts for;
/// the transport is responsible for authenticating that identity.
sealed class RaceCommand {
  const RaceCommand({required this.racerId});

  final String racerId;

  Map<String, Object?> toJson();

  static RaceCommand fromJson(Map<String, Object?> json) {
    final type = json['type'] as String?;
    final racerId = json['racerId'] as String? ?? '';
    switch (type) {
      case 'join':
        return JoinRace(racerId: racerId);
      case 'leave':
        return LeaveRace(racerId: racerId);
      case 'answer':
        return SubmitAnswer(
          racerId: racerId,
          questionIndex: json['questionIndex'] as int? ?? -1,
          optionIndex: json['optionIndex'] as int? ?? -1,
        );
      default:
        throw FormatException('Unknown race command: $type');
    }
  }
}

final class JoinRace extends RaceCommand {
  const JoinRace({required super.racerId});

  @override
  Map<String, Object?> toJson() => {'type': 'join', 'racerId': racerId};
}

final class LeaveRace extends RaceCommand {
  const LeaveRace({required super.racerId});

  @override
  Map<String, Object?> toJson() => {'type': 'leave', 'racerId': racerId};
}

/// A racer's answer. [questionIndex] guards against answers meant for an
/// earlier question; [optionIndex] is the only answer detail the server needs.
final class SubmitAnswer extends RaceCommand {
  const SubmitAnswer({
    required super.racerId,
    required this.questionIndex,
    required this.optionIndex,
  });

  final int questionIndex;
  final int optionIndex;

  @override
  Map<String, Object?> toJson() => {
        'type': 'answer',
        'racerId': racerId,
        'questionIndex': questionIndex,
        'optionIndex': optionIndex,
      };
}

/// Why the server did or did not accept a command.
enum RaceAnswerStatus {
  accepted,
  rejectedUnknownRacer,
  rejectedOutOfPhase,
  rejectedDuplicate,
  rejectedLate,
  rejectedInvalidOption,
  rejectedEliminated,
}

/// The server's private verdict for one racer's action.
class RaceNotice {
  const RaceNotice({
    required this.racerId,
    required this.status,
    this.correct,
    this.progress,
  });

  final String racerId;
  final RaceAnswerStatus status;

  /// Only present for accepted answers.
  final bool? correct;
  final int? progress;

  bool get accepted => status == RaceAnswerStatus.accepted;

  Map<String, Object?> toJson() => {
        'racerId': racerId,
        'status': status.name,
        if (correct != null) 'correct': correct,
        if (progress != null) 'progress': progress,
      };

  static RaceNotice fromJson(Map<String, Object?> json) => RaceNotice(
        racerId: json['racerId'] as String? ?? '',
        status: RaceAnswerStatus.values.byName(json['status'] as String),
        correct: json['correct'] as bool?,
        progress: json['progress'] as int?,
      );
}

/// The public view of the current question. It deliberately has no correct
/// answer and no explanation; those stay on the server.
class QuestionView {
  const QuestionView({
    required this.index,
    required this.id,
    required this.category,
    required this.text,
    required this.options,
    required this.deadlineMs,
  });

  final int index;
  final String id;
  final String category;
  final String text;
  final List<String> options;

  /// Server clock time when the answer window closes.
  final int deadlineMs;

  Map<String, Object?> toJson() => {
        'index': index,
        'id': id,
        'category': category,
        'text': text,
        'options': options,
        'deadlineMs': deadlineMs,
      };

  static QuestionView fromJson(Map<String, Object?> json) => QuestionView(
        index: json['index'] as int,
        id: json['id'] as String,
        category: json['category'] as String,
        text: json['text'] as String,
        options: [
          for (final option in json['options'] as List) option as String,
        ],
        deadlineMs: json['deadlineMs'] as int,
      );
}

/// One racer's authoritative state as broadcast to clients.
class RacerState {
  const RacerState({
    required this.id,
    required this.position,
    required this.progress,
    required this.speed,
    required this.finished,
    required this.eliminated,
    required this.inDanger,
    this.finishedAtMs,
  });

  final String id;
  final int position;
  final int progress;
  final SpeedStatus speed;
  final bool finished;
  final bool eliminated;
  final bool inDanger;
  final int? finishedAtMs;

  Map<String, Object?> toJson() => {
        'id': id,
        'position': position,
        'progress': progress,
        'speed': speed.name,
        'finished': finished,
        'eliminated': eliminated,
        'inDanger': inDanger,
        if (finishedAtMs != null) 'finishedAtMs': finishedAtMs,
      };

  static RacerState fromJson(Map<String, Object?> json) => RacerState(
        id: json['id'] as String,
        position: json['position'] as int,
        progress: json['progress'] as int,
        speed: SpeedStatus.values.byName(json['speed'] as String),
        finished: json['finished'] as bool,
        eliminated: json['eliminated'] as bool,
        inDanger: json['inDanger'] as bool,
        finishedAtMs: json['finishedAtMs'] as int?,
      );
}

/// The complete authoritative race state at one point in time.
class RaceSnapshot {
  const RaceSnapshot({
    required this.matchId,
    required this.phase,
    required this.questionsAsked,
    required this.racers,
    required this.ranking,
    required this.serverTimeMs,
    this.question,
  });

  final String matchId;
  final RacePhase phase;
  final int questionsAsked;

  /// Present only while a question is open.
  final QuestionView? question;
  final List<RacerState> racers;
  final List<String> ranking;

  /// Server clock when this snapshot was taken, for latency estimates.
  final int serverTimeMs;

  RacerState? racerFor(String racerId) {
    for (final racer in racers) {
      if (racer.id == racerId) return racer;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'matchId': matchId,
        'phase': phase.name,
        'questionsAsked': questionsAsked,
        if (question != null) 'question': question!.toJson(),
        'racers': [for (final racer in racers) racer.toJson()],
        'ranking': ranking,
        'serverTimeMs': serverTimeMs,
      };

  static RaceSnapshot fromJson(Map<String, Object?> json) {
    final question = json['question'];
    return RaceSnapshot(
      matchId: json['matchId'] as String,
      phase: RacePhase.values.byName(json['phase'] as String),
      questionsAsked: json['questionsAsked'] as int,
      question: question == null
          ? null
          : QuestionView.fromJson(question as Map<String, Object?>),
      racers: [
        for (final racer in json['racers'] as List)
          RacerState.fromJson(racer as Map<String, Object?>),
      ],
      ranking: [for (final id in json['ranking'] as List) id as String],
      serverTimeMs: json['serverTimeMs'] as int,
    );
  }
}
