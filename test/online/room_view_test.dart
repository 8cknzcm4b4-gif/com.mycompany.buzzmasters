import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:buzz_masters/bm/online/online_race_service.dart';
import 'package:buzz_masters/bm/online/room_view.dart';

/// The app builds live race views from Firestore snapshots. These cases were
/// produced by the real server engine (functions/scripts/fixtures.ts), so the
/// app's view must match the server's field for field.
void main() {
  final cases = (jsonDecode(
          File('test/fixtures/room_views.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  test('fixtures cover every race phase', () {
    expect(cases.map((c) => c['name']), [
      'lobby with readiness',
      'countdown',
      'question open',
      'answered',
      'reveal pause',
      'stale racer',
      'finished',
    ]);
  });

  for (final c in cases) {
    test('local view equals the server view: ${c['name']}', () {
      final view = roomViewFromDoc(
        (c['doc'] as Map).cast<String, dynamic>(),
        'room-1',
        c['uid'] as String,
        (c['mine'] as Map?)?.cast<String, dynamic>(),
        (c['now'] as num).toInt(),
      );
      expect(jsonDecode(jsonEncode(view)), c['view']);
      // And the app parses it.
      final state = RoomState.fromJson(view);
      expect(state.players, isNotEmpty);
    });
  }

  test('deadlines: the app asks the server to tick exactly when one is due', () {
    Map<String, dynamic> doc(String name) => (cases
            .firstWhere((c) => c['name'] == name)['doc'] as Map)
        .cast<String, dynamic>();
    final lobby = doc('lobby with readiness');
    expect(nextDeadline(lobby), lobby['expiresAt']);
    final countdown = doc('countdown');
    expect(nextDeadline(countdown), countdown['startsAt']);
    final open = doc('question open');
    expect(nextDeadline(open), (open['qOpenedAt'] as num) + 8000);
    final reveal = doc('reveal pause');
    expect(nextDeadline(reveal), reveal['qOpenedAt'], reason: 'publish next');
    expect(nextDeadline(doc('finished')), isNull);
  });
}
