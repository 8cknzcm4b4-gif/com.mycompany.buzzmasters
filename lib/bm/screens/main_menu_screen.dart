import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';
import '../race/turbo_race_lobby_screen.dart';
import 'matchmaking_screen.dart';
import 'settings_screen.dart';

/// Screen 5 — Main Menu: player header, primary actions, mode grid, tab bar.
class BmMainMenuScreen extends StatefulWidget {
  const BmMainMenuScreen({super.key});

  @override
  State<BmMainMenuScreen> createState() => _BmMainMenuScreenState();
}

class _BmMainMenuScreenState extends State<BmMainMenuScreen> {
  int _tab = 0;

  static const _tiles = <_MenuTile>[
    _MenuTile('PRACTICE', Icons.school_rounded, Color(0xFF8B5CF6)),
    _MenuTile('DAILY QUIZ', Icons.calendar_today_rounded, Color(0xFF00D8F4)),
    _MenuTile('THEMED QUIZZES', Icons.category_rounded, Color(0xFF3D8BFF)),
    _MenuTile('RANKED PLAY', Icons.military_tech_rounded, Color(0xFFFF8A3D)),
    _MenuTile('TOURNAMENTS', Icons.emoji_events_rounded, Color(0xFFFFCB45)),
    _MenuTile('LEADERBOARDS', Icons.leaderboard_rounded, Color(0xFF35D07F)),
    _MenuTile('MY AVATAR', Icons.person_rounded, Color(0xFF9B6BFF)),
    _MenuTile('REWARDS', Icons.card_giftcard_rounded, Color(0xFFFF4E87)),
    _MenuTile('SHOP', Icons.shopping_cart_rounded, Color(0xFFFFB020)),
    _MenuTile('TURBO RACE', Icons.directions_run_rounded, Color(0xFFFF4E87)),
  ];

  void _openTurboRace() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TurboRaceLobbyScreen()),
    );
  }

  void _openMatchmaking() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BmMatchmakingScreen()),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BmSettingsScreen()),
    );
  }

  void _notBuilt(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: BmColors.panel,
        content: Text(
          '$feature is not implemented yet in this build.',
          style: BmText.body(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          _playerHeader(),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Image.asset('assets/images/bm_logo.png', width: 210),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/bm_hero.png',
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 14),
                  BmButton(
                    label: 'PLAY NOW',
                    icon: Icons.play_arrow_rounded,
                    height: 56,
                    fontSize: 17,
                    onPressed: _openMatchmaking,
                  ),
                  const SizedBox(height: 10),
                  BmButton(
                    label: 'PLAY WITH FRIENDS',
                    icon: Icons.people_alt_rounded,
                    style: BmButtonStyle.cyan,
                    onPressed: () => _notBuilt('Private friend lobbies'),
                  ),
                  const SizedBox(height: 18),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.95,
                    children: [
                      for (final tile in _tiles)
                        _MenuTileCard(
                          tile: tile,
                          onTap: () => switch (tile.label) {
                            'PRACTICE' => _openMatchmaking(),
                            'TURBO RACE' => _openTurboRace(),
                            _ => _notBuilt(tile.label),
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _playerHeader() {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: BmGradients.cyan,
            border: Border.all(color: BmColors.cyan, width: 2),
            boxShadow: bmGlow(BmColors.cyan, blur: 16, opacity: 0.45),
          ),
          alignment: Alignment.center,
          child: Text(
            'A',
            style: BmText.display(20, color: const Color(0xFF08111F)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Alex', style: BmText.title(14)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('LEVEL 1', style: BmText.label(9, color: BmColors.cyan)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: 0.18,
                        minHeight: 5,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        valueColor: const AlwaysStoppedAnimation(BmColors.cyan),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _currency('1,250', BmColors.gold, Icons.monetization_on_rounded),
        const SizedBox(width: 8),
        _currency('45', BmColors.pink, Icons.diamond_rounded),
      ],
    );
  }

  Widget _currency(String value, Color color, IconData icon) {
    return BmPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: color,
      borderRadius: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(value, style: BmText.title(12, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    const items = [
      (Icons.home_rounded, 'Home'),
      (Icons.people_alt_rounded, 'Friends'),
      (Icons.person_rounded, 'Profile'),
      (Icons.settings_rounded, 'Settings'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0C1E).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            InkWell(
              onTap: () {
                // Settings opens as a page, so the tab itself stays on Home.
                if (i == 3) {
                  _openSettings();
                  return;
                }
                setState(() => _tab = i);
                if (i != 0) _notBuilt(items[i].$2);
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      items[i].$1,
                      size: 21,
                      color: _tab == i ? BmColors.gold : BmColors.muted,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      items[i].$2,
                      style: BmText.label(
                        9,
                        color: _tab == i ? BmColors.gold : BmColors.muted,
                        spacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MenuTile {
  const _MenuTile(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

class _MenuTileCard extends StatelessWidget {
  const _MenuTileCard({required this.tile, required this.onTap});

  final _MenuTile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tile.color.withValues(alpha: 0.85),
                tile.color.withValues(alpha: 0.45),
              ],
            ),
            border: Border.all(color: tile.color, width: 1.2),
            boxShadow: bmGlow(tile.color, blur: 16, opacity: 0.35),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tile.icon, color: Colors.white, size: 26),
              const SizedBox(height: 8),
              Text(
                tile.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: BmText.label(9, color: Colors.white, spacing: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
