import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../online/online_race_service.dart';
import '../player/player_profile.dart';
import '../race/time_trial.dart';
import '../race/time_trial_store.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';
import 'profile_screen.dart';

/// Records actually held by this build: the player's race record and their
/// best time trial. Global rankings need the online server, and the screen
/// says so instead of inventing other players.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({
    super.key,
    this.store = const PrefsTimeTrialStore(),
    this.showBack = true,
  });

  final TimeTrialStore store;
  final bool showBack;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late Future<GhostTrack?> _load = _fetch();
  LeaderboardPeriod _period = LeaderboardPeriod.allTime;
  late Future<OnlineResult<List<LeaderboardRow>>> _globalLoad =
      OnlineRace.service.leaderboard(period: _period);
  int _tab = 0;

  void _loadPeriod(LeaderboardPeriod period) {
    final next = OnlineRace.service.leaderboard(period: period);
    setState(() {
      _period = period;
      _globalLoad = next;
    });
  }

  Widget _periods() {
    const labels = {
      LeaderboardPeriod.allTime: 'ALL TIME',
      LeaderboardPeriod.month: 'THIS MONTH',
      LeaderboardPeriod.week: 'THIS WEEK',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          for (final e in labels.entries)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  key: ValueKey('lb-period-${e.key.wire}'),
                  onTap: () => _loadPeriod(e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: _period == e.key
                          ? BmColors.cyan.withValues(alpha: 0.18)
                          : Colors.transparent,
                      border: Border.all(
                          color: _period == e.key
                              ? BmColors.cyan
                              : BmColors.panelEdge),
                    ),
                    child: FittedBox(
                      child: Text(e.value,
                          style: BmText.label(9.5,
                              color: _period == e.key
                                  ? Colors.white
                                  : BmColors.muted)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<GhostTrack?> _fetch() async {
    await PlayerProfileStore.ensureLoaded();
    return widget.store.loadBest();
  }

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          ArenaHeader(
            title: 'LEADERBOARDS',
            subtitle: 'RANKINGS & RECORDS',
            showBack: widget.showBack,
          ),
          const SizedBox(height: 10),
          _tabs(),
          const SizedBox(height: 12),
          Expanded(
            child: _tab == 0 ? _global() : _records(),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    Widget tab(int i, String label) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _tab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: _tab == i ? BmGradients.violet : null,
                boxShadow: _tab == i
                    ? bmGlow(BmColors.violet, blur: 16, opacity: 0.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(label,
                  style: BmText.label(11,
                      color: _tab == i ? Colors.white : BmColors.muted)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: const Color(0xFF080C2A).withValues(alpha: 0.85),
        border: Border.all(color: BmColors.panelEdge),
      ),
      child: Row(children: [tab(0, 'GLOBAL'), tab(1, 'MY RECORDS')]),
    );
  }

  Widget _global() {
    if (!OnlineRace.service.isConfigured) {
      return _state(
        icon: Icons.cloud_off_rounded,
        color: BmColors.gold,
        title: 'GLOBAL RANKINGS OFFLINE',
        body: 'Worldwide rankings are stored on the Buzz Masters server, '
            'which this build is not connected to. No rankings are shown '
            'rather than made-up ones. Your own records are on the next tab.',
        action: BmButton(
          label: 'VIEW MY RECORDS',
          icon: Icons.person_rounded,
          style: BmButtonStyle.cyan,
          height: 46,
          fontSize: 13,
          onPressed: () => setState(() => _tab = 1),
        ),
      );
    }
    return Column(
      children: [
        _periods(),
        Expanded(child: _globalList()),
      ],
    );
  }

  Widget _globalList() {
    return FutureBuilder<OnlineResult<List<LeaderboardRow>>>(
      future: _globalLoad,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(color: BmColors.cyan));
        }
        final result = snap.data!;
        final rows = result.value;
        if (rows == null) {
          return _state(
            icon: Icons.cloud_off_rounded,
            color: BmColors.red,
            title: 'COULD NOT LOAD RANKINGS',
            body: result.message,
            action: BmButton(
              label: 'TRY AGAIN',
              height: 46,
              onPressed: () => _loadPeriod(_period),
            ),
          );
        }
        if (rows.isEmpty) {
          return _state(
            icon: Icons.leaderboard_rounded,
            color: BmColors.cyan,
            title: 'NO RANKINGS YET',
            body: _period == LeaderboardPeriod.allTime
                ? 'Finish an online race to appear on the leaderboard.'
                : 'No online races finished in this period yet.',
          );
        }
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: BmPanel(
                  color: r.isMe
                      ? BmColors.gold
                      : r.rank <= 3
                          ? BmColors.purple
                          : BmColors.panelEdge,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text('#${r.rank}',
                            style: BmText.display(16,
                                color: r.rank == 1
                                    ? BmColors.gold
                                    : Colors.white)),
                      ),
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: BmColors.seatColors[r.color % 6],
                        child: Text(r.name.characters.first.toUpperCase(),
                            style: BmText.display(13, color: BmColors.deep)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(r.isMe ? '${r.name} (you)' : r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BmText.title(14)),
                      ),
                      _mini('${r.wins}', 'WINS', BmColors.gold),
                      _mini('${r.podiums}', 'PODIUMS', BmColors.purple),
                      _mini('${r.races}', 'RACES', BmColors.cyan),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _mini(String value, String label, Color color) => SizedBox(
        width: 50,
        child: Column(
          children: [
            Text(value, style: BmText.display(15, color: color)),
            Text(label, style: BmText.label(6.5)),
          ],
        ),
      );

  Widget _records() {
    return FutureBuilder<GhostTrack?>(
      future: _load,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: BmColors.cyan),
          );
        }
        if (snap.hasError) {
          return _state(
            icon: Icons.error_outline_rounded,
            color: BmColors.red,
            title: 'COULD NOT LOAD RECORDS',
            body: 'Your saved records could not be read.',
            action: BmButton(
              label: 'TRY AGAIN',
              height: 46,
              onPressed: () {
                final next = _fetch();
                setState(() {
                  _load = next;
                });
              },
            ),
          );
        }
        final best = snap.data;
        return ValueListenableBuilder<PlayerStats>(
          valueListenable: PlayerProfileStore.current,
          builder: (context, s, _) {
            if (s.races == 0 && best == null) {
              return _state(
                icon: Icons.flag_rounded,
                color: BmColors.cyan,
                title: 'NO RACES YET',
                body: 'Finish a Practice Race or Time Trial and your records '
                    'appear here.',
              );
            }
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                GestureDetector(
                  key: const ValueKey('leaderboard-me'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const ProfileScreen()),
                  ),
                  child: BmPanel(
                    color: BmColors.gold,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: s.color,
                          child: Text(s.initial,
                              style: BmText.display(18, color: BmColors.deep)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name, style: BmText.title(15)),
                              Text('LEVEL ${s.level} · ${s.xp} XP',
                                  style: BmText.label(9, color: BmColors.cyan)),
                            ],
                          ),
                        ),
                        Text('VIEW PROFILE',
                            style: BmText.label(9, color: BmColors.gold)),
                        const Icon(Icons.chevron_right_rounded,
                            color: BmColors.gold),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _row(Icons.emoji_events_rounded, 'RACE WINS', '${s.wins}',
                    BmColors.gold),
                _row(Icons.military_tech_rounded, 'PODIUM FINISHES',
                    '${s.podiums}', BmColors.purple),
                _row(Icons.flag_rounded, 'RACES COMPLETED', '${s.races}',
                    BmColors.cyan),
                _row(
                    Icons.leaderboard_rounded,
                    'BEST FINISH',
                    s.bestPlacing == 0 ? '—' : 'P${s.bestPlacing}',
                    BmColors.pink),
                _row(Icons.bolt_rounded, 'ANSWER ACCURACY', '${s.accuracy}%',
                    BmColors.green),
                _row(
                    Icons.timer_rounded,
                    'TIME TRIAL BEST',
                    best == null ? '—' : formatRaceTime(best.elapsedMs),
                    BmColors.cyan),
                if (s.recent.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('RECENT FINISHES', style: BmText.label(10)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in s.recent)
                        BmChip(
                          text: 'P$p',
                          color: p == 1
                              ? BmColors.gold
                              : p <= 3
                                  ? BmColors.purple
                                  : BmColors.muted,
                          filled: p == 1,
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _row(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BmPanel(
        color: BmColors.panelEdge,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
                child:
                    Text(label, style: BmText.label(10, color: Colors.white))),
            Text(value, style: BmText.display(18, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _state({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    Widget? action,
  }) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(top: 30),
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.7)),
                boxShadow: bmGlow(color, blur: 26, opacity: 0.3),
              ),
              child: Icon(icon, color: color, size: 34),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: BmText.display(19, color: color)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: BmText.body(13, color: BmColors.muted)),
            if (action != null) ...[const SizedBox(height: 18), action],
          ],
        ),
      ),
    );
  }
}
