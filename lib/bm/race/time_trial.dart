/// Time trial support: a recorded run and the ghost that replays it.
library;

/// One progress reading taken during a run.
class GhostSample {
  const GhostSample({required this.tMs, required this.progress});

  /// Race clock time, in milliseconds from the start.
  final int tMs;
  final int progress;

  Map<String, Object?> toJson() => {'t': tMs, 'p': progress};

  static GhostSample fromJson(Map<String, Object?> json) => GhostSample(
        tMs: json['t'] as int,
        progress: json['p'] as int,
      );
}

/// A completed run, replayable as a ghost.
class GhostTrack {
  const GhostTrack({
    required this.distance,
    required this.elapsedMs,
    required this.samples,
  });

  final int distance;

  /// Finish time of the run this ghost replays.
  final int elapsedMs;

  /// Progress readings ordered by [GhostSample.tMs].
  final List<GhostSample> samples;

  /// Progress the ghost had reached [atMs] into the run, interpolated between
  /// samples so the ghost moves smoothly rather than in steps.
  int progressAt(int atMs) {
    if (samples.isEmpty) return 0;
    if (atMs <= samples.first.tMs) return samples.first.progress;
    for (var i = 1; i < samples.length; i++) {
      final previous = samples[i - 1];
      final next = samples[i];
      if (atMs <= next.tMs) {
        final span = next.tMs - previous.tMs;
        if (span <= 0) return next.progress;
        final fraction = (atMs - previous.tMs) / span;
        return (previous.progress +
                (next.progress - previous.progress) * fraction)
            .round();
      }
    }
    return samples.last.progress;
  }

  Map<String, Object?> toJson() => {
        'distance': distance,
        'elapsedMs': elapsedMs,
        'samples': [for (final sample in samples) sample.toJson()],
      };

  static GhostTrack fromJson(Map<String, Object?> json) => GhostTrack(
        distance: json['distance'] as int,
        elapsedMs: json['elapsedMs'] as int,
        samples: [
          for (final sample in json['samples'] as List)
            GhostSample.fromJson(sample as Map<String, Object?>),
        ],
      );
}

/// Collects progress readings while a time trial runs.
class TimeTrialRunRecorder {
  TimeTrialRunRecorder({required this.distance});

  final int distance;
  final List<GhostSample> _samples = [const GhostSample(tMs: 0, progress: 0)];

  List<GhostSample> get samples => List<GhostSample>.unmodifiable(_samples);

  /// Adds a reading. Readings must arrive in time order; a repeat of the last
  /// time is ignored so the ghost never divides by a zero time span.
  void record({required int atMs, required int progress}) {
    final last = _samples.last;
    if (atMs <= last.tMs) return;
    _samples.add(
      GhostSample(
        tMs: atMs,
        progress: progress.clamp(0, distance),
      ),
    );
  }

  /// The finished run. A run that never reached the finish is not a ghost.
  GhostTrack? build({required int elapsedMs}) {
    if (_samples.last.progress < distance) return null;
    return GhostTrack(
      distance: distance,
      elapsedMs: elapsedMs,
      samples: List<GhostSample>.unmodifiable(_samples),
    );
  }
}

/// Race time as `m:ss.t`, or `s.t` under a minute.
String formatRaceTime(int ms) {
  final total = ms < 0 ? 0 : ms;
  final minutes = total ~/ 60000;
  final seconds = (total % 60000) ~/ 1000;
  final tenths = (total % 1000) ~/ 100;
  final padded = seconds.toString().padLeft(2, '0');
  return minutes > 0 ? '$minutes:$padded.$tenths' : '$seconds.$tenths';
}

/// A signed difference against a ghost, in seconds to one decimal place.
String formatRaceDelta(int deltaMs) {
  final sign = deltaMs < 0 ? '-' : '+';
  return '$sign${(deltaMs.abs() / 1000).toStringAsFixed(1)}s';
}
