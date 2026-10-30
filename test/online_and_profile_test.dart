import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzz_masters/bm/online/online_race_service.dart';
import 'package:buzz_masters/bm/player/player_profile.dart';

void main() {
  group('race codes', () {
    test('accept exactly six digits, with optional spaces or a dash', () {
      expect(RaceCode.validate('482913'), isNull);
      expect(RaceCode.validate('482-913'), isNull);
      expect(RaceCode.validate('482 913'), isNull);
      expect(RaceCode.normalise('482-913'), '482913');
    });

    test('reject empty, short, long and non-digit codes', () {
      expect(RaceCode.validate(''), contains('Enter'));
      expect(RaceCode.validate('12345'), contains('exactly 6'));
      expect(RaceCode.validate('1234567'), contains('exactly 6'));
      expect(RaceCode.validate('12a456'), contains('digits only'));
    });
  });

  group('online service', () {
    test('the unconfigured service never invents a lobby', () async {
      const service = UnconfiguredOnlineRaceService();
      expect(service.isConfigured, isFalse);
      for (final result in [
        await service.join('482913'),
        await service.createRoom(),
        await service.liveRoom(),
      ]) {
        expect(result.ok, isFalse);
        expect(result.error, OnlineError.notConfigured);
      }
      expect((await service.leaderboard()).ok, isFalse);
      expect((await service.friends()).ok, isFalse);
    });

    test('room state parses the server JSON and ranks like the server', () {
      final room = RoomState.fromJson(const {
        'ok': true,
        'room_id': 'r1',
        'code': '482913',
        'status': 'racing',
        'is_host': false,
        'question_number': 4,
        'questions_resolved': 3,
        'rules': {'distance': 100, 'window_ms': 8000, 'max_questions': 30},
        'players': [
          {
            'id': 'a',
            'seat': 1,
            'name': 'Nova',
            'color': 0,
            'progress': 40,
            'is_host': true
          },
          {
            'id': 'b',
            'seat': 2,
            'name': 'Rio',
            'color': 1,
            'progress': 100,
            'finished': true,
            'finished_ms': 52000,
            'is_me': true
          },
          {
            'id': 'c',
            'seat': 3,
            'name': 'Jet',
            'color': 2,
            'progress': 60,
            'eliminated': true
          },
          {
            'id': 'd',
            'seat': 4,
            'name': 'Zed',
            'color': 3,
            'progress': 40,
            'connected': false
          },
        ],
        'question': {
          'index': 3,
          'prompt': 'Q?',
          'options': ['A', 'B'],
          'remaining_ms': 5100
        },
        'my_answer': {'option': 1, 'correct': true, 'delta': 15},
      });
      expect(room.status, RoomStatus.racing);
      expect(room.isLive, isTrue);
      expect(room.hostName, 'Nova');
      expect(room.me!.name, 'Rio');
      expect(room.question!.options, ['A', 'B']);
      expect(room.myAnswer!.delta, 15);
      expect(room.players.last.connected, isFalse);
      // Finisher first; ties on distance break by seat; eliminated last.
      expect(room.positions, {'b': 1, 'a': 2, 'd': 3, 'c': 4});
    });

    test('server error codes become player messages', () {
      expect(const OnlineResult<int>.fail('full').message, contains('full'));
      expect(
          const OnlineResult<int>.fail('expired').message, contains('expired'));
      expect(
          const OnlineResult<int>.fail('mystery').message, contains('mystery'));
    });
  });

  group('player profile', () {
    test('folding races updates wins, podiums, streaks and accuracy', () {
      var s = const PlayerStats();
      s = s.withRace(placing: 1, correctAnswers: 8, answeredQuestions: 10);
      s = s.withRace(placing: 1, correctAnswers: 6, answeredQuestions: 8);
      s = s.withRace(placing: 4, correctAnswers: 2, answeredQuestions: 6);
      expect(s.races, 3);
      expect(s.wins, 2);
      expect(s.podiums, 2);
      expect(s.bestPlacing, 1);
      expect(s.winStreak, 0);
      expect(s.bestWinStreak, 2);
      expect(s.accuracy, 67);
      expect(s.recent, [4, 1, 1]);
    });

    test('level grows with XP and progress stays in range', () {
      const fresh = PlayerStats();
      expect(fresh.level, 1);
      expect(fresh.levelProgress, inInclusiveRange(0, 1));
      const veteran =
          PlayerStats(races: 20, wins: 5, podiums: 10, correct: 150);
      expect(veteran.level, greaterThan(1));
      expect(veteran.levelProgress, inInclusiveRange(0, 1));
      expect(veteran.xpToNext, greaterThan(0));
    });

    test('achievements unlock from real stats only', () {
      final none = Achievement.forStats(const PlayerStats());
      expect(none.where((a) => a.unlocked), isEmpty);
      final some = Achievement.forStats(
          const PlayerStats(races: 1, podiums: 1, wins: 1));
      expect(some.where((a) => a.unlocked).map((a) => a.title),
          containsAll(['First Lap', 'Podium Finisher', 'Champion']));
    });

    test('the store persists and reloads the record', () async {
      SharedPreferences.setMockInitialValues({});
      PlayerProfileStore.resetForTests();
      await PlayerProfileStore.setName('  Nova  ');
      await PlayerProfileStore.recordRace(
          placing: 2, correctAnswers: 5, answeredQuestions: 7);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('bm_player_profile_v1')!)
          as Map<String, dynamic>;
      expect(saved['name'], 'Nova');
      expect(saved['podiums'], 1);

      PlayerProfileStore.resetForTests();
      await PlayerProfileStore.ensureLoaded();
      expect(PlayerProfileStore.current.value.name, 'Nova');
      expect(PlayerProfileStore.current.value.races, 1);
    });
  });
}
