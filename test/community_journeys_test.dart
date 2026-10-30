import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzz_masters/bm/online/join_game_screen.dart';
import 'package:buzz_masters/bm/online/online_lobby_screen.dart';
import 'package:buzz_masters/bm/online/online_race_screen.dart';
import 'package:buzz_masters/bm/online/online_race_service.dart';
import 'package:buzz_masters/bm/player/player_profile.dart';
import 'package:buzz_masters/bm/screens/friends_screen.dart';
import 'package:buzz_masters/bm/screens/leaderboard_screen.dart';
import 'package:buzz_masters/bm/settings/bm_audio_settings.dart';

import 'online/fake_online_server.dart';

Future<void> _frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _open(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await _frames(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BmAudioSettings.resetForTests();
    PlayerProfileStore.resetForTests();
    OnlineRace.service = const UnconfiguredOnlineRaceService();
  });

  testWidgets('quick race opens a public lobby; a second racer appears at once',
      (tester) async {
    final server = FakeOnlineServer();
    OnlineRace.service = server.client('me', 'Nova');
    await _open(tester, const JoinGameScreen());

    await tester.tap(find.byKey(const ValueKey('join-quick')));
    await _frames(tester, 3);
    expect(find.byType(OnlineLobbyScreen), findsOneWidget);
    expect(find.textContaining('PUBLIC · 1 / 6'), findsOneWidget);

    // A second player's Quick Race lands in the same lobby. The lobby polls
    // only every 60 s here, so seeing them within 0.3 s proves the update
    // came through the Realtime signal.
    final lobby =
        tester.widget<OnlineLobbyScreen>(find.byType(OnlineLobbyScreen));
    expect(lobby.initial.isPublic, isTrue);
    await tester.pumpWidget(MaterialApp(
        home: OnlineLobbyScreen(
            initial: lobby.initial,
            pollInterval: const Duration(seconds: 60))));
    await tester.pump();
    final rival = server.client('rival', 'Rio', color: 3);
    final joined = await rival.quickJoin();
    expect(joined.value!.roomId, lobby.initial.roomId);
    await _frames(tester, 3);
    expect(find.text('Rio'), findsOneWidget);
    expect(find.textContaining('PUBLIC · 2 / 6'), findsOneWidget);
  });

  testWidgets('quick race explains itself when the server is not connected',
      (tester) async {
    await _open(tester, const JoinGameScreen());
    final button = find.byKey(const ValueKey('join-quick'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await _frames(tester, 2);
    expect(find.byType(OnlineLobbyScreen), findsNothing);
    expect(find.text('ONLINE SERVER NOT CONNECTED'), findsOneWidget);
  });

  testWidgets('guests ready up and the host sees everyone ready',
      (tester) async {
    final server = FakeOnlineServer();
    final host = server.client('host', 'Nova');
    final room = (await host.createRoom()).value!;
    final guest = server.client('guest', 'Rio', color: 2);
    final joined = (await guest.join(room.code)).value!;

    OnlineRace.service = guest;
    await _open(tester, OnlineLobbyScreen(initial: joined));
    expect(find.text("TAP WHEN YOU'RE READY"), findsOneWidget);
    expect(find.text('YOU · NOT READY'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lobby-ready')));
    await _frames(tester, 3);
    expect(find.text('YOU · READY'), findsOneWidget);
    expect(find.text('READY · WAITING FOR NOVA'), findsOneWidget);

    OnlineRace.service = host;
    final hostView = (await host.roomState(room.roomId)).value!;
    expect(hostView.allReady, isTrue);
    await tester.pumpWidget(MaterialApp(
        home:
            OnlineLobbyScreen(key: const ValueKey('host'), initial: hostView)));
    await _frames(tester, 3);
    expect(find.text('START RACE · ALL READY'), findsOneWidget);
    expect(find.text('READY'), findsOneWidget);

    // The guest changes their mind; the host's label follows.
    await guest.setReady(room.roomId, false);
    await _frames(tester, 3);
    expect(find.text('START RACE · 1/2 READY'), findsOneWidget);
  });

  testWidgets('a racer reports the open question by its number',
      (tester) async {
    final server = FakeOnlineServer();
    final me = server.client('me', 'Nova');
    final room = (await me.createRoom()).value!;
    await server.client('r', 'Rio').join(room.code);
    await me.startRace(room.roomId);
    server.advance(3100);
    final live = (await me.roomState(room.roomId)).value!;
    OnlineRace.service = me;
    await _open(tester, OnlineRaceScreen(initial: live));

    await tester.tap(find.byKey(const ValueKey('online-report-question')));
    await _frames(tester, 4);
    expect(find.text('REPORT THIS QUESTION'), findsOneWidget);
    await tester.tap(find.text('The answer is wrong'));
    await _frames(tester, 4);
    expect(server.reports, [('me', 'q0@${room.roomId}', 'wrong_answer')]);
    expect(find.text('Thanks — the question was reported.'), findsOneWidget);
  });

  testWidgets('rankings switch between all time, this month and this week',
      (tester) async {
    final server = FakeOnlineServer();
    final me = server.client('me', 'Nova');
    OnlineRace.service = me;
    await _open(tester, const LeaderboardScreen());
    expect(me.periodsAsked, [LeaderboardPeriod.allTime]);
    expect(find.text('Finish an online race to appear on the leaderboard.'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lb-period-week')));
    await _frames(tester, 3);
    await tester.tap(find.byKey(const ValueKey('lb-period-month')));
    await _frames(tester, 3);
    expect(me.periodsAsked, [
      LeaderboardPeriod.allTime,
      LeaderboardPeriod.week,
      LeaderboardPeriod.month,
    ]);
    expect(find.text('No online races finished in this period yet.'),
        findsOneWidget);
  });

  testWidgets('blocking a friend removes them and keeps them out of lobbies',
      (tester) async {
    final server = FakeOnlineServer();
    final me = server.client('me', 'Nova');
    final rio = server.client('rio', 'Rio', color: 2);
    final myCode = (await me.friends()).value!.myCode;
    await rio.sendFriendRequest(myCode);
    await me.respondToFriend('rio', true);
    OnlineRace.service = me;
    await _open(tester, const FriendsScreen());
    expect(find.text('FRIENDS · 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('friend-menu-rio')));
    await _frames(tester, 4);
    await tester.tap(find.text('Report'));
    await _frames(tester, 4);
    await tester.tap(find.text('Offensive name'));
    await _frames(tester, 4);
    expect(server.reports, [('me', 'rio', 'offensive_name')]);

    await tester.tap(find.byKey(const ValueKey('friend-menu-rio')));
    await _frames(tester, 4);
    await tester.tap(find.text('Block'));
    await _frames(tester, 4);
    expect(find.text('Block Rio?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('block-confirm')));
    await _frames(tester, 4);
    expect(find.text('FRIENDS · 0'), findsOneWidget);

    final lobby = (await me.createRoom()).value!;
    expect((await rio.join(lobby.code)).error, 'blocked');
    expect((await rio.sendFriendRequest(myCode)).error, 'not_found');
  });
}
