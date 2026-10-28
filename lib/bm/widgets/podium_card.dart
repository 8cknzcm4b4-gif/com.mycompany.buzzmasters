import 'package:flutter/material.dart';

import '../design/bm_theme.dart';

/// One illuminated contestant podium with avatar, name and live score.
class PodiumCard extends StatelessWidget {
  const PodiumCard({
    super.key,
    required this.color,
    required this.name,
    required this.score,
    this.active = false,
    this.eliminated = false,
    this.status,
    this.width = 92,
    this.height = 128,
  });

  final Color color;
  final String name;
  final String score;
  final bool active;
  final bool eliminated;

  /// Optional reaction glyph shown when a contestant answers.
  final IconData? status;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final accent = eliminated ? const Color(0xFF4A4C66) : color;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 350),
      opacity: eliminated ? 0.45 : 1,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 260),
        scale: active ? 1.06 : 1,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accent.withOpacity(active ? 0.55 : 0.30),
                BmColors.panel.withValues(alpha: 0.92),
              ],
            ),
            border: Border.all(
              color: accent.withOpacity(active ? 1 : 0.75),
              width: active ? 2.2 : 1.3,
            ),
            boxShadow: [
              ...bmGlow(accent,
                  blur: active ? 30 : 14, opacity: active ? 0.65 : 0.3),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Avatar(accent: accent, name: name, size: width * 0.52),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BmText.body(11, color: Colors.white)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                score,
                style: BmText.display(20, color: accent),
              ),
              if (status != null) Icon(status, size: 15, color: BmColors.gold),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.accent, required this.name, required this.size});

  final Color accent;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.95),
            accent.withValues(alpha: 0.55),
            accent.withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(color: accent, width: 2),
        boxShadow: bmGlow(accent, blur: 14, opacity: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: BmText.display(size * 0.48, color: const Color(0xFF15122B)),
      ),
    );
  }
}
