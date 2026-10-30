import 'dart:async';

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../monetisation/ui/admin_dashboard_screen.dart';
import '../settings/bm_audio_settings.dart';
import '../widgets/bm_button.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';
import 'how_to_play_screen.dart';
import 'profile_screen.dart';

/// Settings: sound, music and haptic preferences (saved on change), plus
/// links to the player profile, the rules and the admin dashboard.
class BmSettingsScreen extends StatefulWidget {
  const BmSettingsScreen({super.key});

  @override
  State<BmSettingsScreen> createState() => _BmSettingsScreenState();
}

class _BmSettingsScreenState extends State<BmSettingsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(BmAudioSettings.ensureLoaded());
  }

  void _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          const ArenaHeader(title: 'SETTINGS', subtitle: 'SOUND & FEEDBACK'),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _ToggleRow(
                    icon: Icons.volume_up_rounded,
                    color: BmColors.cyan,
                    label: 'SOUND EFFECTS',
                    sub: 'Countdown, answers, overtakes and finish',
                    setting: BmAudioSettings.soundEffects,
                    onChanged: BmAudioSettings.setSoundEnabled,
                  ),
                  const SizedBox(height: 10),
                  _ToggleRow(
                    icon: Icons.music_note_rounded,
                    color: BmColors.purple,
                    label: 'MUSIC',
                    sub: 'Arena soundtrack on the menus',
                    setting: BmAudioSettings.music,
                    onChanged: BmAudioSettings.setMusicEnabled,
                  ),
                  const SizedBox(height: 10),
                  _ToggleRow(
                    icon: Icons.vibration_rounded,
                    color: BmColors.pink,
                    label: 'HAPTIC FEEDBACK',
                    sub: 'Vibrate on taps, answers and overtakes',
                    setting: BmAudioSettings.haptics,
                    onChanged: BmAudioSettings.setHapticsEnabled,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Saved on this device automatically.',
                    textAlign: TextAlign.center,
                    style: BmText.body(11,
                        color: BmColors.muted, weight: FontWeight.w400),
                  ),
                  const SizedBox(height: 18),
                  _LinkRow(
                    icon: Icons.person_rounded,
                    label: 'PLAYER PROFILE',
                    sub: 'Name, colour and achievements',
                    onTap: () => _push(const ProfileScreen()),
                  ),
                  const SizedBox(height: 10),
                  _LinkRow(
                    icon: Icons.help_outline_rounded,
                    label: 'HOW TO PLAY',
                    sub: 'Race rules and scoring',
                    onTap: () => _push(const HowToPlayScreen()),
                  ),
                  const SizedBox(height: 10),
                  _LinkRow(
                    icon: Icons.admin_panel_settings_rounded,
                    label: 'TOURNAMENT ADMIN',
                    sub: 'Monetisation and tournament dashboard',
                    onTap: () =>
                        _push(const AdminMonetisationDashboardScreen()),
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

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: BmPanel(
        color: BmColors.panelEdge,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: BmColors.cyan, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: BmText.label(10, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(sub, style: BmText.body(11, color: BmColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: BmColors.muted),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.sub,
    required this.setting,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String sub;
  final ValueNotifier<bool> setting;
  final Future<void> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: setting,
      builder: (context, value, _) => BmPanel(
        color: value ? color : BmColors.panelEdge,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: value ? 0.22 : 0.08),
                border: Border.all(
                  color: color.withValues(alpha: value ? 0.85 : 0.3),
                ),
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: BmText.label(10, color: Colors.white)),
                  const SizedBox(height: 3),
                  Text(sub, style: BmText.body(11, color: BmColors.muted)),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: (next) => unawaited(onChanged(next)),
              activeThumbColor: BmColors.gold,
              activeTrackColor: BmColors.gold.withValues(alpha: 0.45),
              inactiveThumbColor: BmColors.muted,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
            ),
          ],
        ),
      ),
    );
  }
}
