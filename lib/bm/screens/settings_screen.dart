import 'dart:async';

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../settings/bm_audio_settings.dart';
import '../widgets/bm_panel.dart';
import '../widgets/studio_background.dart';

/// Screen — Settings: the audio feedback preferences the race cues read.
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

  @override
  Widget build(BuildContext context) {
    return StudioScaffold(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  'SETTINGS',
                  textAlign: TextAlign.center,
                  style: BmText.display(18, color: BmColors.gold),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 4),
          Text('Sound & Feedback', style: BmText.body(12)),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _ToggleRow(
                    icon: Icons.volume_up_rounded,
                    color: BmColors.cyan,
                    label: 'SOUND EFFECTS',
                    sub: 'Buzzer, countdown and answer cues',
                    setting: BmAudioSettings.soundEffects,
                    onChanged: BmAudioSettings.setSoundEnabled,
                  ),
                  const SizedBox(height: 12),
                  _ToggleRow(
                    icon: Icons.vibration_rounded,
                    color: BmColors.pink,
                    label: 'HAPTIC FEEDBACK',
                    sub: 'Vibrate on buzz-in',
                    setting: BmAudioSettings.haptics,
                    onChanged: BmAudioSettings.setHapticsEnabled,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Saved on this device and used by every race.',
                    textAlign: TextAlign.center,
                    style: BmText.body(
                      11,
                      color: BmColors.muted,
                      weight: FontWeight.w400,
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
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: value ? 0.22 : 0.10),
                border: Border.all(
                  color: color.withValues(alpha: value ? 0.8 : 0.35),
                ),
              ),
              child: Icon(icon, size: 19, color: Colors.white),
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
