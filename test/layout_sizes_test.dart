import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buzz_masters/bm/monetisation/ui/shop_screen.dart';
import 'package:buzz_masters/bm/monetisation/ui/vip_screen.dart';
import 'package:buzz_masters/bm/online/join_game_screen.dart';
import 'package:buzz_masters/bm/online/online_lobby_screen.dart';
import 'package:buzz_masters/bm/online/online_race_screen.dart';
import 'package:buzz_masters/bm/online/online_race_service.dart';
import 'package:buzz_masters/bm/player/player_profile.dart';
import 'package:buzz_masters/bm/race/race_practice_screen.dart';
import 'package:buzz_masters/bm/race/time_trial_screen.dart';
import 'package:buzz_masters/bm/race/turbo_race_lobby_screen.dart';
import 'package:buzz_masters/bm/screens/friends_screen.dart';
import 'package:buzz_masters/bm/screens/how_to_play_screen.dart';
import 'package:buzz_masters/bm/screens/leaderboard_screen.dart';
import 'package:buzz_masters/bm/screens/legal_screen.dart';
import 'package:buzz_masters/bm/screens/main_menu_screen.dart';
import 'package:buzz_masters/bm/screens/profile_screen.dart';
import 'package:buzz_masters/bm/screens/settings_screen.dart';
import 'package:buzz_masters/bm/screens/splash_screen.dart';
import 'package:buzz_masters/bm/screens/welcome_screen.dart';
import 'package:buzz_masters/bm/settings/bm_audio_settings.dart';

import 'online/fake_online_server.dart';

/// Logical sizes (points) of supported iPhones, smallest to largest.
const _phones = <String, Size>{
  'iPhone SE (1st gen)': Size(320, 568),
  'iPhone SE (3rd gen)': Size(375, 667),
  'iPhone 15': Size(393, 852),
  'iPhone 16 Pro Max': Size(440, 956),
};

/// Pumps [screen] at [size] and fails on any layout overflow or exception.
Future<void> _render(WidgetTester tester, Size size, Widget screen,
    {Duration settle = const Duration(milliseconds: 600)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // Capture full reports, so a failure names the overflowing widget.
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await tester.pumpWidget(MaterialApp(home: screen));
    for (var t = Duration.zero;
        t < settle;
        t += const Duration(milliseconds: 100)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  } finally {
    FlutterError.onError = previous;
  }
  if (errors.isNotEmpty) fail(errors.first.toString());
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BmAudioSettings.resetForTests();
    PlayerProfileStore.resetForTests();
    OnlineRace.service = const UnconfiguredOnlineRaceService();
  });

  for (final phone in _phones.entries) {
    group(phone.key, () {
      final screens = <String, Widget Function()>{
        'splash': () => const BmSplashScreen(next: SizedBox()),
        'welcome': () => const BmWelcomeScreen(),
        'dashboard': () => const BmMainMenuScreen(),
        'race lobby': () => const TurboRaceLobbyScreen(),
        'join game': () => const JoinGameScreen(),
        'leaderboard': () => const LeaderboardScreen(),
        'profile': () => const ProfileScreen(),
        'friends': () => const FriendsScreen(),
        'settings': () => const BmSettingsScreen(),
        'how to play': () => const HowToPlayScreen(),
        'privacy': () => const LegalScreen(page: LegalPage.privacy),
        'terms': () => const LegalScreen(page: LegalPage.terms),
        'VIP': () => const VipMembershipScreen(),
        'shop': () => const ShopScreen(),
      };
      for (final s in screens.entries) {
        testWidgets(s.key, (tester) async {
          await _render(tester, phone.value, s.value());
        });
      }

      testWidgets('practice race: countdown, question, results',
          (tester) async {
        await _render(tester, phone.value, const RacePracticeScreen(),
            settle: const Duration(seconds: 5));
        for (var i = 0;
            i < 4000 && find.text('RESULTS').evaluate().isEmpty;
            i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('RESULTS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('time trial', (tester) async {
        await _render(tester, phone.value, const TimeTrialScreen(),
            settle: const Duration(seconds: 5));
      });

      testWidgets('online lobby and race with six racers', (tester) async {
        final server = FakeOnlineServer();
        final me = server.client('me', 'Maximilian', color: 0);
        final room = (await me.createRoom()).value!;
        for (var i = 0; i < 5; i++) {
          await server
              .client('p$i', 'Racer Number $i', color: i + 1)
              .join(room.code);
        }
        OnlineRace.service = me;
        final lobby = (await me.roomState(room.roomId)).value!;
        await _render(tester, phone.value, OnlineLobbyScreen(initial: lobby));

        final started = (await me.startRace(room.roomId)).value!;
        server.advance(3100);
        await _render(tester, phone.value, OnlineRaceScreen(initial: started),
            settle: const Duration(seconds: 2));
        expect(find.text('POSITION'), findsOneWidget);
      });
    });
  }
}
