import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzz_masters/bm/online/join_game_screen.dart';
import 'package:buzz_masters/bm/online/online_race_service.dart';
import 'package:buzz_masters/bm/player/player_profile.dart';
import 'package:buzz_masters/bm/race/race_practice_screen.dart';
import 'package:buzz_masters/bm/race/turbo_race_lobby_screen.dart';
import 'package:buzz_masters/bm/screens/how_to_play_screen.dart';
import 'package:buzz_masters/bm/screens/leaderboard_screen.dart';
import 'package:buzz_masters/bm/screens/main_menu_screen.dart';
import 'package:buzz_masters/bm/screens/profile_screen.dart';
import 'package:buzz_masters/bm/screens/settings_screen.dart';
import 'package:buzz_masters/bm/screens/welcome_screen.dart';
import 'package:buzz_masters/bm/settings/bm_audio_settings.dart';
import 'package:buzz_masters/bm/widgets/bm_panel.dart';

/// A server stand-in for the join flow: 123456 is an open lobby, 111111 is
/// full, 222222 has expired, anything else does not exist.
class _FakeServer implements OnlineRaceService {
  @override
  bool get isConfigured => true;

  @override
  Future<JoinResult> join(String code) async => switch (code) {
        '123456' => JoinResult.joined(LobbySession(
            code: code,
            lobbyId: 'lobby-$code',
            hostName: 'Sam',
            players: const ['Sam', 'Player'],
            joinedAt: DateTime.now(),
          )),
        '111111' => const JoinResult.failed(JoinFailure.full),
        '222222' => const JoinResult.failed(JoinFailure.expired),
        _ => const JoinResult.failed(JoinFailure.notFound),
      };

  @override
  Future<JoinResult> resume(LobbySession previous) => join(previous.code);
}

/// The arena animates forever, so pump frames instead of settling.
Future<void> _frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openWelcome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: BmWelcomeScreen()));
  await _frames(tester);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back').last);
  await _frames(tester);
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const ValueKey('race-code-field')), code);
  await tester.tap(find.text('JOIN RACE'));
  await _frames(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BmAudioSettings.resetForTests();
    PlayerProfileStore.resetForTests();
    OnlineRace.service = const UnconfiguredOnlineRaceService();
  });

  testWidgets('welcome → join game validates codes and reports the server',
      (tester) async {
    await _openWelcome(tester);
    // No genuine session was ever joined, so there is nothing to resume.
    expect(find.text('RESUME LAST SESSION'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('welcome-get-started')));
    await _frames(tester);
    expect(find.byType(JoinGameScreen), findsOneWidget);

    await _enterCode(tester, '12345');
    expect(find.text('Race codes are exactly 6 digits.'), findsOneWidget);

    await _enterCode(tester, '482913');
    expect(find.textContaining('not available in this build'), findsOneWidget);
    expect(find.byType(OnlineLobbyScreen), findsNothing);

    await _back(tester);
    expect(find.byType(BmWelcomeScreen), findsOneWidget);
  });

  testWidgets('welcome → join → lobby, then resume returns to the same lobby',
      (tester) async {
    OnlineRace.service = _FakeServer();
    await _openWelcome(tester);

    await tester.tap(find.byKey(const ValueKey('welcome-get-started')));
    await _frames(tester);

    await _enterCode(tester, '999999');
    expect(find.text(JoinFailure.notFound.message), findsOneWidget);
    await _enterCode(tester, '111111');
    expect(find.text(JoinFailure.full.message), findsOneWidget);
    await _enterCode(tester, '222222');
    expect(find.text(JoinFailure.expired.message), findsOneWidget);

    await _enterCode(tester, '123-456');
    expect(find.byType(OnlineLobbyScreen), findsOneWidget);
    expect(find.text('CODE 123456'), findsOneWidget);
    expect(find.text('Hosted by Sam'), findsOneWidget);

    // Back to the welcome screen without leaving the lobby.
    await _back(tester);
    expect(find.byType(BmWelcomeScreen), findsOneWidget);
    expect(find.text('RESUME LAST SESSION'), findsOneWidget);
    expect(find.text('Race code 123456'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('welcome-resume')));
    await _frames(tester);
    expect(find.byType(OnlineLobbyScreen), findsOneWidget);

    // Leaving forgets the session, so the resume card disappears.
    await tester.tap(find.text('LEAVE LOBBY'));
    await _frames(tester);
    expect(find.byType(BmWelcomeScreen), findsOneWidget);
    expect(find.text('RESUME LAST SESSION'), findsNothing);
  });

  testWidgets('welcome → settings → change music → saved → back home',
      (tester) async {
    await _openWelcome(tester);
    await tester.tap(find.byKey(const ValueKey('welcome-settings')));
    await _frames(tester);
    expect(find.byType(BmSettingsScreen), findsOneWidget);

    await tester.tap(find.byType(Switch).at(1));
    await _frames(tester, 3);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(BmAudioSettings.musicKey), isFalse);

    await _back(tester);
    expect(find.byType(BmWelcomeScreen), findsOneWidget);
  });

  testWidgets('welcome → leaderboard → player profile → back', (tester) async {
    await PlayerProfileStore.setName('Nova');
    await PlayerProfileStore.recordRace(
        placing: 1, correctAnswers: 6, answeredQuestions: 8);
    await _openWelcome(tester);

    await tester.tap(find.byKey(const ValueKey('welcome-leaderboard')));
    await _frames(tester);
    expect(find.byType(LeaderboardScreen), findsOneWidget);
    // Global rankings say they are offline instead of inventing players.
    expect(find.text('GLOBAL RANKINGS OFFLINE'), findsOneWidget);

    await tester.tap(find.text('MY RECORDS'));
    await _frames(tester);
    expect(find.text('Nova'), findsOneWidget);
    expect(find.text('RACE WINS'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('leaderboard-me')));
    await _frames(tester);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('CHAMPION'), findsOneWidget);

    await _back(tester);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.byType(LeaderboardScreen), findsOneWidget);
    await _back(tester);
    expect(find.byType(BmWelcomeScreen), findsOneWidget);
  });

  testWidgets('welcome → how to play shows the engine rules → back',
      (tester) async {
    await _openWelcome(tester);
    await tester.tap(find.byKey(const ValueKey('welcome-info')));
    await _frames(tester);
    expect(find.byType(HowToPlayScreen), findsOneWidget);
    expect(find.text('SCORING'), findsOneWidget);
    await tester.tap(find.text('GOT IT'));
    await _frames(tester);
    expect(find.byType(BmWelcomeScreen), findsOneWidget);
  });

  testWidgets('welcome → play now → every dashboard tab opens a real screen',
      (tester) async {
    await _openWelcome(tester);
    await tester.tap(find.byKey(const ValueKey('welcome-play')));
    await _frames(tester);
    expect(find.byType(BmMainMenuScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab-Race')));
    await _frames(tester);
    expect(find.text('TURBO TRIVIA RACE'), findsWidgets);
    expect(find.byKey(const ValueKey('lobby-practice')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab-Ranks')));
    await _frames(tester);
    expect(find.text('LEADERBOARDS'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab-Friends')));
    await _frames(tester);
    expect(find.text('FRIENDS NEED ONLINE PLAY'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab-Profile')));
    await _frames(tester);
    expect(find.text('PLAYER PROFILE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab-Home')));
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('menu-race-now')));
    await _frames(tester);
    expect(find.byKey(const ValueKey('lobby-practice')), findsOneWidget);
  });

  testWidgets('welcome → practice → questions → results → home',
      (tester) async {
    await _openWelcome(tester);
    await tester.tap(find.text('PRACTICE RACE'));
    await _frames(tester);
    expect(find.byType(RacePracticeScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AnswerTile), findsNWidgets(4));
    await tester.tap(find.byType(AnswerTile).first);
    await tester.pump();

    for (var i = 0; i < 4000 && find.text('RESULTS').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('RESULTS'), findsOneWidget);
    expect(PlayerProfileStore.current.value.races, 1);
    expect(PlayerProfileStore.current.value.answered, greaterThanOrEqualTo(1));

    await tester.tap(find.text('BACK TO LOBBY'));
    await _frames(tester);
    expect(find.byType(BmWelcomeScreen), findsOneWidget);
  });

  testWidgets('race lobby offers every way in and no dead buttons',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: TurboRaceLobbyScreen()));
    await _frames(tester);

    await tester.tap(find.text('JOIN BY CODE'));
    await _frames(tester);
    expect(find.byType(JoinGameScreen), findsOneWidget);
    await _back(tester);

    await tester.tap(find.byKey(const ValueKey('lobby-practice')));
    await _frames(tester);
    expect(find.byType(RacePracticeScreen), findsOneWidget);
  });
}
