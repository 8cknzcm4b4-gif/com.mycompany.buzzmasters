/// Builds a member's view of a race room from the Firestore room document,
/// in exactly the JSON shape the server returns (functions/src/engine.ts
/// `stateFor`). Lets the app redraw from live snapshots without calling the
/// server for every frame; the server still decides every transition.
///
/// [nowMs] is the server clock as estimated by the app.
Map<String, dynamic> roomViewFromDoc(
  Map<String, dynamic> r,
  String roomId,
  String uid,
  Map<String, dynamic>? mine,
  int nowMs,
) {
  int i(Object? v) => v is num ? v.toInt() : 0;
  int? n(Object? v) => v is num ? v.toInt() : null;
  const distance = 100, windowMs = 8000, dangerFree = 3, dangerMax = 10;
  const staleMs = 20000;

  final status = '${r['status']}';
  final hostId = '${r['hostId']}';
  final racers = ((r['racers'] as Map?) ?? const {})
      .values
      .map((p) => (p as Map).cast<String, dynamic>())
      .toList()
    ..sort((a, b) => i(a['seat']).compareTo(i(b['seat'])));
  final resolved = i(r['questionsResolved']);
  final currentQ = i(r['currentQ']);
  final qOpenedAt = n(r['qOpenedAt']);
  final startsAt = n(r['startsAt']);
  final question = (r['question'] as Map?)?.cast<String, dynamic>();

  bool active(Map<String, dynamic> p) =>
      p['finishedMs'] == null && p['eliminated'] != true;

  final open = status == 'racing' &&
      qOpenedAt != null &&
      nowMs >= qOpenedAt &&
      question != null &&
      i(question['index']) == currentQ;

  final results = (r['results'] as List?)
      ?.map((x) => (x as Map).cast<String, dynamic>())
      .toList();

  return {
    'ok': true,
    'server_now': nowMs,
    'room_id': roomId,
    'code': '${r['code']}',
    'status': status,
    'is_public': r['isPublic'] == true,
    'host_id': hostId,
    'is_host': hostId == uid,
    'all_ready': racers.every((p) =>
        p['uid'] == hostId || p['leftAt'] != null || p['ready'] == true),
    'countdown_ms': status == 'countdown' && startsAt != null
        ? (startsAt - nowMs).clamp(0, 1 << 31)
        : null,
    'question_number': currentQ + 1,
    'questions_resolved': resolved,
    'next_question_in_ms':
        status == 'racing' && qOpenedAt != null && nowMs < qOpenedAt
            ? qOpenedAt - nowMs
            : null,
    'last_correct_index': n(r['lastCorrectIndex']),
    'rules': const {
      'distance': distance,
      'window_ms': windowMs,
      'max_questions': 30,
      'max_seats': 6,
      'min_players': 2,
    },
    'players': [
      for (final p in racers)
        {
          'id': p['uid'],
          'seat': i(p['seat']),
          'name': p['name'],
          'color': i(p['color']),
          'progress': i(p['progress']),
          'speed': p['speed'] ?? 'stopped',
          'finished': p['finishedMs'] != null,
          'finished_ms': n(p['finishedMs']),
          'eliminated': p['eliminated'] == true,
          'danger': active(p) &&
              resolved >= dangerFree &&
              i(p['progress']) <= dangerMax,
          'connected':
              p['leftAt'] == null && i(p['lastSeen']) > nowMs - staleMs,
          'left': p['leftAt'] != null,
          'ready': p['ready'] == true || p['uid'] == hostId,
          'is_me': p['uid'] == uid,
          'is_host': p['uid'] == hostId,
        },
    ],
    'question': open
        ? {
            ...question,
            'remaining_ms': (windowMs - (nowMs - qOpenedAt)).clamp(0, windowMs),
          }
        : null,
    'my_answer': status == 'racing' && mine != null && i(mine['q']) == currentQ
        ? {
            'option': mine['option'],
            'correct': mine['correct'] == true,
            'delta': i(mine['delta']),
          }
        : null,
    'results': status == 'finished' && results != null
        ? [
            for (final x in results)
              {
                'id': x['uid'],
                'placing': i(x['placing']),
                'name': x['name'],
                'color': i(x['color']),
                'progress': i(x['progress']),
                'finished': x['finished'] == true,
                'eliminated': x['eliminated'] == true,
                'correct': i(x['correct']),
                'answered': i(x['answered']),
                'is_me': x['uid'] == uid,
              },
          ]
        : null,
  };
}

/// The next moment the server has a transition due for this room, if any:
/// the countdown ending, a question opening, a question window closing, or
/// a lobby expiring. The app asks the server to tick at that moment.
int? nextDeadline(Map<String, dynamic> r) {
  int? n(Object? v) => v is num ? v.toInt() : null;
  final qOpenedAt = n(r['qOpenedAt']);
  switch ('${r['status']}') {
    case 'lobby':
      return n(r['expiresAt']);
    case 'countdown':
      return n(r['startsAt']);
    case 'racing':
      if (qOpenedAt == null) return null;
      final q = r['question'] as Map?;
      final published = q != null && n(q['index']) == n(r['currentQ']);
      return published ? qOpenedAt + 8000 : qOpenedAt;
    default:
      return null;
  }
}
