import 'dart:async';

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../player/player_profile.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';

/// Player profile: editable name and racing colour, level, race record and
/// achievements, all read from [PlayerProfileStore].
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.showBack = true});

  final bool showBack;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(PlayerProfileStore.ensureLoaded());
  }

  Future<void> _editName(PlayerStats s) async {
    final controller = TextEditingController(text: s.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BmColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: BmColors.cyan.withValues(alpha: 0.6)),
        ),
        title: Text('RACER NAME', style: BmText.display(18)),
        content: TextField(
          key: const ValueKey('profile-name-field'),
          controller: controller,
          autofocus: true,
          maxLength: 16,
          style: BmText.title(16),
          cursorColor: BmColors.cyan,
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: BmColors.muted)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: BmColors.cyan)),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('CANCEL', style: BmText.label(11)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text('SAVE', style: BmText.label(11, color: BmColors.gold)),
          ),
        ],
      ),
    );
    if (name != null) await PlayerProfileStore.setName(name);
  }

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ValueListenableBuilder<PlayerStats>(
        valueListenable: PlayerProfileStore.current,
        builder: (context, s, _) => Column(
          children: [
            ArenaHeader(
              title: 'PLAYER PROFILE',
              subtitle: 'LEVEL ${s.level}',
              showBack: widget.showBack,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _identity(s),
                  const SizedBox(height: 12),
                  _statsGrid(s),
                  const SizedBox(height: 16),
                  Text('ACHIEVEMENTS',
                      style: BmText.label(11, color: BmColors.gold)),
                  const SizedBox(height: 8),
                  for (final a in Achievement.forStats(s))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _achievement(a),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Saved on this device. Cloud sync arrives with Buzz '
                    'Masters accounts.',
                    textAlign: TextAlign.center,
                    style: BmText.body(10.5, color: BmColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identity(PlayerStats s) {
    return BmPanel(
      color: s.color,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 70,
                height: 70,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    Color.lerp(s.color, Colors.white, 0.35)!,
                    s.color,
                  ]),
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: bmGlow(s.color, blur: 22, opacity: 0.7),
                ),
                child: Text(s.initial,
                    style: BmText.display(32, color: BmColors.deep)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BmText.display(24)),
                        ),
                        IconButton(
                          tooltip: 'Edit name',
                          onPressed: () => _editName(s),
                          icon: const Icon(Icons.edit_rounded,
                              color: BmColors.cyan, size: 18),
                        ),
                      ],
                    ),
                    Text('LEVEL ${s.level} · ${s.xp} XP',
                        style: BmText.label(10, color: BmColors.cyan)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: s.levelProgress,
                        minHeight: 7,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation(BmColors.gold),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('${s.xpToNext} XP to level ${s.level + 1}',
                        style: BmText.body(10, color: BmColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('RACING COLOUR', style: BmText.label(9)),
              for (var i = 0; i < BmColors.seatColors.length; i++)
                GestureDetector(
                  onTap: () => PlayerProfileStore.setColor(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BmColors.seatColors[i],
                      border: Border.all(
                        color: i == s.colorIndex % BmColors.seatColors.length
                            ? Colors.white
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(PlayerStats s) {
    final stats = [
      ('RACES', '${s.races}', BmColors.cyan),
      ('WINS', '${s.wins}', BmColors.gold),
      ('PODIUMS', '${s.podiums}', BmColors.purple),
      ('ACCURACY', '${s.accuracy}%', BmColors.green),
      ('BEST', s.bestPlacing == 0 ? '—' : 'P${s.bestPlacing}', BmColors.pink),
      ('STREAK', '${s.bestWinStreak}', BmColors.gold),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.45,
      children: [
        for (final (label, value, color) in stats)
          BmPanel(
            color: color,
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: BmText.display(22)),
                Text(label, style: BmText.label(8, color: color)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _achievement(Achievement a) {
    final color = a.unlocked ? BmColors.gold : BmColors.muted;
    return BmPanel(
      color: a.unlocked ? BmColors.gold : BmColors.panelEdge,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(a.unlocked ? a.icon : Icons.lock_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title.toUpperCase(),
                    style: BmText.label(10,
                        color: a.unlocked ? Colors.white : BmColors.muted)),
                Text(a.detail, style: BmText.body(11, color: BmColors.muted)),
                if (!a.unlocked) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: a.progress,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation(BmColors.cyan),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (a.unlocked)
            const Icon(Icons.check_circle_rounded,
                color: BmColors.green, size: 20),
        ],
      ),
    );
  }
}

/// Small helper so other screens can open the profile.
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context) => BmIconButton(
        icon: Icons.person_rounded,
        tooltip: 'Profile',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
        ),
      );
}
