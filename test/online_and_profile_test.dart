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
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('the unconfigured service never invents a lobby', () async {
      const service = UnconfiguredOnlineRaceService();
      expect(service.isConfigured, isFalse);
      final result = await service.join('482913');
      expect(result.ok, isFalse);
      expect(result.failure, JoinFailure.notConfigured);
    });

    test('nothing is resumable until a join was confirmed', () async {
      expect(await OnlineRace.lastResumable(), isNull);
    });

    test('a remembered lobby is resumable only inside the window', () async {
      final joined = DateTime(2026, 10, 29, 12);
      await OnlineRace.remember(LobbySession(
        code: '482913',
        lobbyId: 'lobby-1',
        hostName: 'Sam',
        players: const ['Sam'],
        joinedAt: joined,
      ));
      final soon = await OnlineRace.lastResumable(
          now: joined.add(const Duration(minutes: 30)));
      expect(soon?.code, '482913');
      final late = await OnlineRace.lastResumable(
          now: joined.add(const Duration(hours: 3)));
      expect(late, isNull);

      await OnlineRace.forget();
      expect(await OnlineRace.lastResumable(now: joined), isNull);
    });

    test('a corrupt saved session is ignored', () async {
      SharedPreferences.setMockInitialValues(
          {'bm_last_online_session_v1': '{not json'});
      expect(await OnlineRace.lastResumable(), isNull);
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
