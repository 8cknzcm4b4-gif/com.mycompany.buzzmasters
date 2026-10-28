import 'package:flutter/material.dart';

import 'design/bm_theme.dart';
import 'screens/gameplay_screen.dart';
import 'screens/main_menu_screen.dart';
import 'screens/matchmaking_screen.dart';
import 'screens/welcome_screen.dart';

/// Buzz Masters app shell. The imported FlutterFlow pages remain on disk but
/// are no longer routed; this shell is the reference-matched presentation.
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
      ),
      home: _home(),
    );
  }

  /// Optional QA / deep-link entry point: `?screen=menu|lobby|game`.
  Widget _home() {
    switch (Uri.base.queryParameters['screen']) {
      case 'menu':
        return const BmMainMenuScreen();
      case 'lobby':
        return const BmMatchmakingScreen();
      case 'game':
        return const BmGameplayScreen();
      default:
        return const BmWelcomeScreen();
    }
  }
}
