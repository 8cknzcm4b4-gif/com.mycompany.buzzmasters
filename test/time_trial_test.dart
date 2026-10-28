import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzz_masters/bm/race/time_trial.dart';
import 'package:buzz_masters/bm/race/time_trial_store.dart';

void main() {
  test('ghost progress interpolates between samples', () {
    const track = GhostTrack(
      distance: 100,
      elapsedMs: 2000,
      samples: [
        GhostSample(tMs: 0, progress: 0),
        GhostSample(tMs: 1000, progress: 10),
        GhostSample(tMs: 2000, progress: 30),
      ],
    );

    expect(track.progressAt(0), 0);
    expect(track.progressAt(500), 5);
    expect(track.progressAt(1500), 20);
    expect(track.progressAt(2000), 30);
    expect(track.progressAt(9000), 30);
    expect(track.progressAt(-5), 0);
  });

  test('recorder keeps readings ordered and clamps progress', () {
    final recorder = TimeTrialRunRecorder(distance: 100);

    recorder.record(atMs: 100, progress: 150);
    recorder.record(atMs: 100, progress: 20);
    recorder.record(atMs: 50, progress: 5);

    expect(recorder.samples.length, 2);
    expect(recorder.samples.last.progress, 100);
  });

  test('an unfinished run produces no ghost', () {
    final recorder = TimeTrialRunRecorder(distance: 100);
    recorder.record(atMs: 500, progress: 40);

    expect(recorder.build(elapsedMs: 500), isNull);
  });

  test('a finished run produces a ghost at the finish', () {
    final recorder = TimeTrialRunRecorder(distance: 100);
    recorder.record(atMs: 500, progress: 40);
    recorder.record(atMs: 900, progress: 100);

    final track = recorder.build(elapsedMs: 900);

    expect(track, isNotNull);
    expect(track!.elapsedMs, 900);
    expect(track.progressAt(500), 40);
    expect(track.progressAt(700), 70);
    expect(track.progressAt(900), 100);
  });

  test('ghost survives a json round trip', () {
    const track = GhostTrack(
      distance: 100,
      elapsedMs: 4230,
      samples: [
        GhostSample(tMs: 0, progress: 0),
        GhostSample(tMs: 4230, progress: 100),
      ],
    );

    final round = GhostTrack.fromJson(
      Map<String, Object?>.from(
        jsonDecode(jsonEncode(track.toJson())) as Map,
      ),
    );

    expect(round.distance, 100);
    expect(round.elapsedMs, 4230);
    expect(round.progressAt(2115), 50);
  });

  test('race times and deltas format to one decimal place', () {
    expect(formatRaceTime(0), '0.0');
    expect(formatRaceTime(42300), '42.3');
    expect(formatRaceTime(63000), '1:03.0');
    expect(formatRaceDelta(-1200), '-1.2s');
    expect(formatRaceDelta(800), '+0.8s');
  });

  test('prefs store persists and loads the best ghost', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const store = PrefsTimeTrialStore();
    const track = GhostTrack(
      distance: 100,
      elapsedMs: 4230,
      samples: [
        GhostSample(tMs: 0, progress: 0),
        GhostSample(tMs: 4230, progress: 100),
      ],
    );

    await store.saveBest(track);
    final loaded = await store.loadBest();

    expect(loaded, isNotNull);
    expect(loaded!.elapsedMs, 4230);
    expect(loaded.samples.length, 2);
  });

  test('prefs store ignores a corrupt save', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'bm_time_trial_best_100': 'not json',
    });
    const store = PrefsTimeTrialStore();

    expect(await store.loadBest(), isNull);
  });
}
