import 'package:flutter/material.dart';

import 'design/bm_theme.dart';
import 'race/race_practice_screen.dart';
import 'race/turbo_race_lobby_screen.dart';
import 'screens/gameplay_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/main_menu_screen.dart';
import 'screens/matchmaking_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';

/// Buzz Masters app shell — the Neon Turbo Quiz Arena build.
///
/// This is the app `main()` runs. The FlutterFlow pages in `lib/pages/` are
/// not routed from here.
class BuzzMastersApp extends StatelessWidget {
  const BuzzMastersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Buzz Masters',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: BmColors.deep,
        colorScheme: const ColorScheme.dark(
          primary: BmColors.gold,
          secondary: BmColors.cyan,
          surface: BmColors.midnight,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: _home(),
    );
  }

  /// Optional QA / deep-link entry point:
  /// `?screen=welcome|menu|lobby|race|ranks|classic|game`.
  Widget _home() {
    return switch (Uri.base.queryParameters['screen']) {
      'welcome' => const BmWelcomeScreen(),
      'menu' => const BmMainMenuScreen(),
      'lobby' => const TurboRaceLobbyScreen(),
      'race' => const RacePracticeScreen(),
      'ranks' => const LeaderboardScreen(),
      'classic' => const BmMatchmakingScreen(),
      'game' => const BmGameplayScreen(),
      _ => const BmSplashScreen(next: BmWelcomeScreen()),
    };
  }
}
