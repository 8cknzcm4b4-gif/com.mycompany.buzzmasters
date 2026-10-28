import 'dart:async';

import 'package:flutter/foundation.dart';

import '../race_model.dart';
import 'race_protocol.dart';
import 'race_server.dart';

/// The network seam between a client and the race server.
///
/// A real implementation would carry these streams over a WebSocket; the code
/// above it only ever sees snapshots and notices.
abstract class RaceTransport {
  Stream<RaceSnapshot> get snapshots;
  Stream<RaceNotice> get notices;

  /// Latest snapshot known to the transport, used to seed a new session.
  RaceSnapshot? get current;

  void send(RaceCommand command);
  Future<void> close();
}

/// Runs the server in-process for single-device play and tests.
class LoopbackRaceTransport implements RaceTransport {
  LoopbackRaceTransport({
    required this.server,
    this.racerId = 'you',
    this.autoTick = false,
    this.tickInterval = const Duration(milliseconds: 100),
  }) {
    server.join(racerId);
    if (autoTick) {
      _timer = Timer.periodic(tickInterval, (_) => server.tick());
    }
  }

  final RaceServer server;
  final String racerId;
  final bool autoTick;
  final Duration tickInterval;

  final StreamController<RaceNotice> _notices =
      StreamController<RaceNotice>.broadcast();
  Timer? _timer;

  @override
  Stream<RaceSnapshot> get snapshots => server.snapshots;

  @override
  Stream<RaceNotice> get notices => _notices.stream;

  @override
  RaceSnapshot? get current => server.snapshot();

  @override
  void send(RaceCommand command) {
    final notice = server.handle(command);
    if (!_notices.isClosed) _notices.add(notice);
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    await _notices.close();
  }
}

/// A client's view of one race.
///
/// It sends intents and renders snapshots. It cannot change progress, scores or
/// phase: those only ever arrive from the server.
class RaceSession {
  RaceSession({required this.transport, required this.racerId}) {
    snapshots.value = transport.current;
    _snapshotSub = transport.snapshots.listen(_onSnapshot);
    _noticeSub =
        transport.notices.listen((notice) => lastNotice.value = notice);
  }

  final RaceTransport transport;
  final String racerId;

  final ValueNotifier<RaceSnapshot?> snapshots =
      ValueNotifier<RaceSnapshot?>(null);
  final ValueNotifier<RaceNotice?> lastNotice =
      ValueNotifier<RaceNotice?>(null);

  late final StreamSubscription<RaceSnapshot> _snapshotSub;
  late final StreamSubscription<RaceNotice> _noticeSub;
  int? _answeredQuestion;

  RaceSnapshot? get snapshot => snapshots.value;

  /// True when this racer may still answer the open question.
  bool get canAnswer {
    final snap = snapshots.value;
    if (snap == null || snap.phase != RacePhase.questionActive) return false;
    final question = snap.question;
    if (question == null) return false;
    if (_answeredQuestion == question.index) return false;
    final me = snap.racerFor(racerId);
    return me != null && !me.eliminated && !me.finished;
  }

  void join() => transport.send(JoinRace(racerId: racerId));

  void leave() => transport.send(LeaveRace(racerId: racerId));

  /// Sends an answer, or returns false when no answer is possible right now.
  /// The server still validates the answer; this is only a local guard.
  bool requestAnswer(int optionIndex) {
    final snap = snapshots.value;
    final question = snap?.question;
    if (snap == null || question == null || !canAnswer) return false;
    _answeredQuestion = question.index;
    transport.send(
      SubmitAnswer(
        racerId: racerId,
        questionIndex: question.index,
        optionIndex: optionIndex,
      ),
    );
    return true;
  }

  void _onSnapshot(RaceSnapshot snap) {
    snapshots.value = snap;
    final current = snap.question?.index;
    if (_answeredQuestion != null && _answeredQuestion != current) {
      _answeredQuestion = null;
    }
  }

  Future<void> dispose() async {
    await _snapshotSub.cancel();
    await _noticeSub.cancel();
    snapshots.dispose();
    lastNotice.dispose();
  }
}
