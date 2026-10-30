import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzz_masters/bm/online/join_game_screen.dart';
import 'package:buzz_masters/bm/online/online_lobby_screen.dart';
import 'package:buzz_masters/bm/online/online_race_screen.dart';
import 'package:buzz_masters/bm/online/online_race_service.dart';
import 'package:buzz_masters/bm/player/player_profile.dart';
import 'package:buzz_masters/bm/race/race_practice_screen.dart';
import 'package:buzz_masters/bm/race/turbo_race_lobby_screen.dart';
import 'package:buzz_masters/bm/screens/how_to_play_screen.dart';
import 'package:buzz_masters/bm/screens/legal_screen.dart';
import 'package:buzz_masters/bm/monetisation/ui/vip_screen.dart';
import 'package:buzz_masters/bm/screens/leaderboard_screen.dart';
import 'package:buzz_masters/bm/screens/main_menu_screen.dart';
import 'package:buzz_masters/bm/screens/profile_screen.dart';
import 'package:buzz_masters/bm/screens/settings_screen.dart';
import 'package:buzz_masters/bm/screens/welcome_screen.dart';
import 'package:buzz_masters/bm/settings/bm_audio_settings.dart';
import 'package:buzz_masters/bm/widgets/bm_panel.dart';

import 'online/fake_online_server.dart';

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

  testWidgets('welcome → join game → enter code → server lobby → resume',
      (tester) async {
    final server = FakeOnlineServer();
    final host = server.client('host', 'Sam');
    final lobby = (await host.createRoom()).value!;
    OnlineRace.service = server.client('me', 'Nova');
    await _openWelcome(tester);
    // Nothing on the server yet for this player.
    expect(find.text('RESUME LAST SESSION'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('welcome-get-started')));
    await _frames(tester);
    // The field filters letters out, so this arrives as five digits.
    await _enterCode(tester, '12a456');
    expect(find.text('Race codes are exactly 6 digits.'), findsOneWidget);
    final missing = lobby.code == '000000' ? '000001' : '000000';
    await _enterCode(tester, missing);
    expect(find.text(OnlineError.message('not_found')), findsOneWidget);

    await _enterCode(
        tester, '${lobby.code.substring(0, 3)}-${lobby.code.substring(3)}');
    expect(find.byType(OnlineLobbyScreen), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Nova'), findsOneWidget);
    // A guest is not ready until they say so; the host starts the race.
    expect(find.text("TAP WHEN YOU'RE READY"), findsOneWidget);
    expect(find.text('YOU · NOT READY'), findsOneWidget);
    expect(find.text('HOST'), findsOneWidget);

    // Lobby → welcome without leaving: the server keeps the seat, so it
    // offers a resume.
    Navigator.of(tester.element(find.byType(OnlineLobbyScreen))).pop();
    await _frames(tester);
    expect(find.byType(BmWelcomeScreen), findsOneWidget);
    expect(find.text('RESUME LAST SESSION'), findsOneWidget);
    expect(find.text('Race code ${lobby.code}'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('welcome-resume')));
    await _frames(tester);
    expect(find.byType(OnlineLobbyScreen), findsOneWidget);

    // Leaving gives the seat up; the resume card goes with it.
    await _back(tester);
    expect(find.byType(BmWelcomeScreen), findsOneWidget);
    expect(find.text('RESUME LAST SESSION'), findsNothing);
    expect(server.rooms[lobby.roomId]!.players.containsKey('me'), isFalse);
  });

  testWidgets('full and expired races give clear errors', (tester) async {
    final server = FakeOnlineServer();
    final old = (await server.client('o', 'Old').createRoom()).value!;
    server.advance(31 * 60 * 1000); // the old lobby expires
    final full = (await server.client('h', 'Host').createRoom()).value!;
    for (var i = 0; i < 5; i++) {
      await server.client('p$i', 'P$i').join(full.code);
    }
    OnlineRace.service = server.client('me', 'Nova');

    await _openWelcome(tester);
    await tester.tap(find.byKey(const ValueKey('welcome-get-started')));
    await _frames(tester);
    await _enterCode(tester, full.code);
    expect(find.text(OnlineError.message('full')), findsOneWidget);
    await _enterCode(tester, old.code);
    expect(find.text(OnlineError.message('expired')), findsOneWidget);
  });

  testWidgets('host online race → rival joins → start → race → results → home',
      (tester) async {
    final server = FakeOnlineServer();
    OnlineRace.service = server.client('me', 'Nova');
    final rival = server.client('rival', 'Rio', color: 3);
    await _openWelcome(tester);
    await tester.tap(find.byKey(const ValueKey('welcome-play')));
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('tab-Race')));
    await _frames(tester);

    await tester.tap(find.byKey(const ValueKey('lobby-host')));
    await _frames(tester);
    expect(find.byType(OnlineLobbyScreen), findsOneWidget);
    final room = server.rooms.values.single;
    expect(find.text('NEED 2 RACERS TO START'), findsOneWidget);

    await rival.join(room.code);
    await _frames(tester, 12); // the lobby polls every second
    expect(find.text('Rio'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('online-start')));
    await _frames(tester);
    expect(find.byType(OnlineRaceScreen), findsOneWidget);
    expect(find.text('GET READY'), findsOneWidget);

    // The countdown ends on the server clock and the first question opens.
    server.advance(3100);
    await _frames(tester, 10);
    expect(find.byType(AnswerTile), findsWidgets);

    // Answer every question right and fast; the rival stays silent.
    var answered = 0;
    for (var guard = 0; guard < 40 && room.status == 'racing'; guard++) {
      if (find.byType(AnswerTile).evaluate().isEmpty) {
        server.advance(1600); // reveal pause, then the next question opens
        await _frames(tester, 10);
        continue;
      }
      final right = server.correctIndexFor(room.id);
      await tester.ensureVisible(find.byType(AnswerTile).at(right));
      await tester.pump();
      await tester.tap(find.byType(AnswerTile).at(right));
      await _frames(tester, 3);
      answered++;
      // Correct, or (once the rival is out and only we answer) the server
      // resolves at once and the reveal shows the answer instead.
      // The winning answer ends the race at once.
      if (room.status == 'racing') {
        expect(
            find.textContaining('Correct!').evaluate().length +
                find.byKey(const ValueKey('online-reveal')).evaluate().length,
            1);
      }
      server.advance(8100); // the rival times out, the question resolves
      await _frames(tester, 10);
    }
    expect(answered, 7); // 7 fast answers x 15 = 105 -> the finish
    expect(room.status, 'finished');
    for (var i = 0; i < 30 && find.text('RESULTS').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('RESULTS'), findsOneWidget);
    expect(find.text('YOU WIN THE RACE!'), findsOneWidget);
    expect(PlayerProfileStore.current.value.wins, 1);

    await tester.tap(find.text('BACK TO LOBBY'));
    await _frames(tester);
    expect(find.byKey(const ValueKey('lobby-host')), findsOneWidget);

    // The win is on the global leaderboard.
    await tester.tap(find.byKey(const ValueKey('tab-Ranks')));
    await _frames(tester);
    expect(find.text('Nova (you)'), findsOneWidget);
  });

  testWidgets('a dropped connection shows reconnecting, then recovers',
      (tester) async {
    final server = FakeOnlineServer();
    final me = server.client('me', 'Nova');
    final room = (await me.createRoom()).value!;
    await server.client('r', 'Rio').join(room.code);
    final started = (await me.startRace(room.roomId)).value!;
    OnlineRace.service = me;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(MaterialApp(home: OnlineRaceScreen(initial: started)));
    await _frames(tester, 3);

    me.offline = true;
    await _frames(tester, 10);
    expect(find.byKey(const ValueKey('online-reconnecting')), findsOneWidget);
    me.offline = false;
    server.advance(3100);
    await _frames(tester, 10);
    expect(find.byKey(const ValueKey('online-reconnecting')), findsNothing);
    expect(find.byType(AnswerTile), findsWidgets);
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

  Future<void> openSettings(WidgetTester tester) async {
    await _openWelcome(tester);
    await tester.tap(find.byKey(const ValueKey('welcome-settings')));
    await _frames(tester);
    expect(find.byType(BmSettingsScreen), findsOneWidget);
  }

  Future<void> tapRow(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(find.text(label), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(label));
    await _frames(tester);
  }

  testWidgets('settings → privacy policy and terms open and close',
      (tester) async {
    await openSettings(tester);
    expect(find.text('Guest on this device · online accounts not connected'),
        findsOneWidget);
    await tapRow(tester, 'PRIVACY POLICY');
    expect(find.byType(LegalScreen), findsOneWidget);
    expect(find.text('ON YOUR DEVICE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('DELETING YOUR DATA'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('DELETING YOUR DATA'), findsOneWidget);
    await tester.tap(find.text('DONE'));
    await _frames(tester);
    await tapRow(tester, 'TERMS OF USE');
    expect(find.text('FAIR PLAY'), findsOneWidget);
    await _back(tester);
    expect(find.byType(BmSettingsScreen), findsOneWidget);
  });

  testWidgets('settings → VIP & restore purchases opens the VIP screen',
      (tester) async {
    await openSettings(tester);
    await tapRow(tester, 'VIP & RESTORE PURCHASES');
    expect(find.byType(VipMembershipScreen), findsOneWidget);
  });

  testWidgets('settings → erase device data needs DELETE typed, then erases',
      (tester) async {
    await PlayerProfileStore.setName('Nova');
    await PlayerProfileStore.recordRace(
        placing: 1, correctAnswers: 5, answeredQuestions: 6);
    await openSettings(tester);
    await tapRow(tester, 'ERASE DATA ON THIS DEVICE');
    expect(find.text('ERASE DEVICE DATA?'), findsOneWidget);

    // Not confirmed yet: the delete button stays disabled.
    await tester.tap(find.text('DELETE'));
    await _frames(tester, 2);
    expect(find.text('ERASE DEVICE DATA?'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('delete-confirm-field')), 'delete');
    await tester.pump();
    await tester.tap(find.text('DELETE'));
    await _frames(tester);
    expect(find.text('Device data erased.'), findsOneWidget);
    expect(PlayerProfileStore.current.value.name, 'Player');
    expect(PlayerProfileStore.current.value.races, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });
}
