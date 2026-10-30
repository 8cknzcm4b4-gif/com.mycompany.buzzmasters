import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../monetisation/ui/rewards_screen.dart';
import '../monetisation/ui/shop_screen.dart';
import '../monetisation/ui/tournaments_screen.dart';
import '../monetisation/ui/vip_screen.dart';
import '../online/join_game_screen.dart';
import '../player/player_profile.dart';
import '../race/race_arena.dart';
import '../race/race_model.dart';
import '../race/race_practice_screen.dart';
import '../race/time_trial_screen.dart';
import '../race/turbo_race_lobby_screen.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';
import 'friends_screen.dart';
import 'how_to_play_screen.dart';
import 'leaderboard_screen.dart';
import 'matchmaking_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'welcome_screen.dart';

/// Main dashboard: player header, featured Turbo Race, quick modes, the rest
/// of the game, and a bottom bar whose every tab is a real screen.
class BmMainMenuScreen extends StatefulWidget {
  const BmMainMenuScreen({super.key});

  @override
  State<BmMainMenuScreen> createState() => _BmMainMenuScreenState();
}

class _BmMainMenuScreenState extends State<BmMainMenuScreen> {
  int _tab = 0;

  /// Bumped each time a live-data tab is opened, so it refetches.
  final _visits = List<int>.filled(5, 0);

  void _select(int i) => setState(() {
        _tab = i;
        _visits[i]++;
      });

  static const _tabs = [
    (Icons.home_rounded, 'Home'),
    (Icons.sports_score_rounded, 'Race'),
    (Icons.leaderboard_rounded, 'Ranks'),
    (Icons.people_alt_rounded, 'Friends'),
    (Icons.person_rounded, 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(PlayerProfileStore.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BmColors.deep,
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _HomeTab(onTab: _select),
                const TurboRaceLobbyScreen(showBack: false),
                LeaderboardScreen(
                    key: ValueKey('ranks-${_visits[2]}'), showBack: false),
                FriendsScreen(
                    key: ValueKey('friends-${_visits[3]}'), showBack: false),
                const ProfileScreen(showBack: false),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF060925),
        border: Border(
          top: BorderSide(color: BmColors.violet.withValues(alpha: 0.5)),
        ),
        boxShadow: bmGlow(BmColors.violet, blur: 24, opacity: 0.25),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: InkWell(
                    key: ValueKey('tab-${_tabs[i].$2}'),
                    onTap: () => _select(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: _tab == i ? BmGradients.violet : null,
                              boxShadow: _tab == i
                                  ? bmGlow(BmColors.violet,
                                      blur: 14, opacity: 0.6)
                                  : null,
                            ),
                            child: Icon(
                              _tabs[i].$1,
                              size: 22,
                              color: _tab == i ? Colors.white : BmColors.muted,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _tabs[i].$2.toUpperCase(),
                            style: BmText.label(8.5,
                                color:
                                    _tab == i ? Colors.white : BmColors.muted,
                                spacing: 0.8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.onTab});

  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    void push(Widget screen) =>
        Navigator.of(context).push(arenaRoute<void>(screen));

    final quick = [
      _Tile('PRACTICE', 'vs 5 CPU racers', Icons.sports_score_rounded,
          BmColors.gold, () => push(const RacePracticeScreen())),
      _Tile('TIME TRIAL', 'beat your ghost', Icons.timer_rounded, BmColors.cyan,
          () => push(const TimeTrialScreen())),
      _Tile('JOIN GAME', '6-digit code', Icons.vpn_key_rounded, BmColors.pink,
          () => push(const JoinGameScreen())),
    ];
    final more = [
      _Tile('CLASSIC SHOW', 'buzzer rounds', Icons.campaign_rounded,
          BmColors.purple, () => push(const BmMatchmakingScreen())),
      _Tile('TOURNAMENTS', 'sponsored events', Icons.emoji_events_rounded,
          BmColors.gold, () => push(const SponsoredTournamentsScreen())),
      _Tile('REWARDS', 'daily rewards', Icons.card_giftcard_rounded,
          BmColors.pink, () => push(const DailyRewardsScreen())),
      _Tile('SHOP', 'cosmetics', Icons.storefront_rounded, BmColors.cyan,
          () => push(const ShopScreen())),
      _Tile('MY ITEMS', 'inventory', Icons.backpack_rounded, BmColors.green,
          () => push(const InventoryScreen())),
      _Tile('HOW TO PLAY', 'rules & scoring', Icons.help_outline_rounded,
          BmColors.purple, () => push(const HowToPlayScreen())),
    ];

    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      showFloor: false,
      child: Column(
        children: [
          _header(context, push),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                _FeaturedRace(onRace: () => onTab(1)),
                const SizedBox(height: 14),
                _sectionTitle('QUICK PLAY'),
                Row(
                  children: [
                    for (final (i, t) in quick.indexed) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: _TileCard(tile: t, tall: true)),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _sectionTitle('MORE TO PLAY'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.5,
                  children: [for (final t in more) _TileCard(tile: t)],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Row(
          children: [
            Container(width: 3, height: 14, color: BmColors.cyan),
            const SizedBox(width: 8),
            Text(text, style: BmText.label(11, color: Colors.white)),
          ],
        ),
      );

  Widget _header(BuildContext context, void Function(Widget) push) {
    return ValueListenableBuilder<PlayerStats>(
      valueListenable: PlayerProfileStore.current,
      builder: (context, s, _) => Row(
        children: [
          GestureDetector(
            onTap: () => onTab(4),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  Color.lerp(s.color, Colors.white, 0.3)!,
                  s.color,
                ]),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: bmGlow(s.color, blur: 16, opacity: 0.6),
              ),
              child: Text(s.initial,
                  style: BmText.display(21, color: BmColors.deep)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BmText.display(18)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text('LVL ${s.level}',
                        style: BmText.label(9, color: BmColors.cyan)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: s.levelProgress,
                          minHeight: 5,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          valueColor:
                              const AlwaysStoppedAnimation(BmColors.cyan),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => push(const VipMembershipScreen()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: BmGradients.gold,
                boxShadow: bmGlow(BmColors.gold, blur: 14, opacity: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_rounded,
                      size: 15, color: Color(0xFF2A1600)),
                  const SizedBox(width: 4),
                  Text('VIP',
                      style:
                          BmText.display(13, color: const Color(0xFF2A1600))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          BmIconButton(
            icon: Icons.settings_rounded,
            tooltip: 'Settings',
            onPressed: () => push(const BmSettingsScreen()),
          ),
        ],
      ),
    );
  }
}

/// Featured Turbo Race card with an animated preview of the race track.
class _FeaturedRace extends StatefulWidget {
  const _FeaturedRace({required this.onRace});

  final VoidCallback onRace;

  @override
  State<_FeaturedRace> createState() => _FeaturedRaceState();
}

class _FeaturedRaceState extends State<_FeaturedRace> {
  static const _ids = ['a', 'b', 'c', 'd', 'e', 'f'];
  final _rng = math.Random(5);
  late List<int> _progress = [for (final _ in _ids) _rng.nextInt(30)];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted) return;
      setState(() {
        _progress = [
          for (final p in _progress)
            p >= 100 ? 0 : math.min(100, p + 5 + _rng.nextInt(12)),
        ];
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 230,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border:
            Border.all(color: BmColors.gold.withValues(alpha: 0.7), width: 1.4),
        boxShadow: bmGlow(BmColors.violet, blur: 30, opacity: 0.45),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: RaceArena(
                distance: 100,
                positions: const {},
                running: true,
                showStandings: false,
                racers: [
                  for (var i = 0; i < _ids.length; i++)
                    ArenaRacer(
                      id: _ids[i],
                      name: '',
                      color: BmColors.seatColors[i],
                      progress: _progress[i],
                      speed: i.isEven ? SpeedStatus.fast : SpeedStatus.cruising,
                    ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    BmColors.deep.withValues(alpha: 0.7),
                    Colors.transparent,
                    BmColors.deep.withValues(alpha: 0.85),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 14,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BmChip(
                      text: 'Featured', color: BmColors.gold, filled: true),
                  const SizedBox(height: 6),
                  Text('TURBO TRIVIA RACE',
                      style: BmText.display(26).copyWith(letterSpacing: 1.5)),
                  Text('6 lanes · answer fast · reach the finish',
                      style: BmText.body(11.5, color: const Color(0xFFD5DAF5))),
                ],
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: BmButton(
                key: const ValueKey('menu-race-now'),
                label: 'RACE NOW',
                icon: Icons.play_arrow_rounded,
                height: 50,
                fontSize: 16,
                onPressed: widget.onRace,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile {
  const _Tile(this.label, this.sub, this.icon, this.color, this.onTap);

  final String label;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _TileCard extends StatefulWidget {
  const _TileCard({required this.tile, this.tall = false});

  final _Tile tile;
  final bool tall;

  @override
  State<_TileCard> createState() => _TileCardState();
}

class _TileCardState extends State<_TileCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tile;
    final icon = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(colors: [
          t.color,
          Color.lerp(t.color, Colors.black, 0.35)!,
        ]),
        boxShadow: bmGlow(t.color, blur: 12, opacity: 0.55),
      ),
      child: Icon(t.icon, color: Colors.white, size: 20),
    );
    final text = Column(
      crossAxisAlignment:
          widget.tall ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(t.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BmText.display(13.5)),
        Text(t.sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BmText.body(9.5, color: BmColors.muted)),
      ],
    );
    return GestureDetector(
      key: ValueKey('tile-${t.label}'),
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: t.onTap,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 100),
        child: BmPanel(
          color: t.color,
          padding: EdgeInsets.symmetric(
              horizontal: 10, vertical: widget.tall ? 14 : 8),
          child: widget.tall
              ? Column(children: [icon, const SizedBox(height: 8), text])
              : Row(children: [
                  icon,
                  const SizedBox(width: 10),
                  Expanded(child: text),
                ]),
        ),
      ),
    );
  }
}
