import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';

/// Dark glass panel with a neon edge, used for the question display and
/// secondary information blocks.
class BmPanel extends StatelessWidget {
  const BmPanel({
    super.key,
    required this.child,
    this.color = BmColors.violet,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
    this.fillOpacity = 0.9,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final double borderRadius;
  final double fillOpacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: const Color(0xFF0E1030).withOpacity(fillOpacity),
        border: Border.all(color: color.withValues(alpha: 0.75), width: 1.4),
        boxShadow: bmGlow(color, blur: 20, opacity: 0.28),
      ),
      child: child,
    );
  }
}

/// `ROUND 1 / THE QUALIFIER` style badge.
class RoundBadge extends StatelessWidget {
  const RoundBadge({
    super.key,
    required this.round,
    required this.title,
    this.color = BmColors.cyan,
  });

  final int round;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFF0B1030).withValues(alpha: 0.9),
        border: Border.all(color: color, width: 1.5),
        boxShadow: bmGlow(color, blur: 18, opacity: 0.45),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ROUND $round', style: BmText.label(10, color: color)),
          Text(
            title.toUpperCase(),
            style: BmText.title(13, color: Colors.white)
                .copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Circular countdown with a depleting neon arc.
class TimerRing extends StatelessWidget {
  const TimerRing({
    super.key,
    required this.secondsLeft,
    required this.total,
    this.size = 62,
  });

  final double secondsLeft;
  final double total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final progress = total <= 0 ? 0.0 : (secondsLeft / total).clamp(0.0, 1.0);
    final color = progress > 0.5
        ? BmColors.cyan
        : progress > 0.2
            ? BmColors.gold
            : BmColors.red;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress: progress, color: color),
        child: Center(
          child: Text(
            '${secondsLeft.ceil()}',
            style: BmText.display(size * 0.42, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white.withValues(alpha: 0.12),
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.5),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Answer option tile (A/B/C/D) with selected + revealed states.
class AnswerTile extends StatelessWidget {
  const AnswerTile({
    super.key,
    required this.letter,
    required this.text,
    this.selected = false,
    this.correct = false,
    this.wrong = false,
    this.enabled = true,
    this.onTap,
  });

  final String letter;
  final String text;
  final bool selected;
  final bool correct;
  final bool wrong;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = correct
        ? BmColors.green
        : wrong
            ? BmColors.red
            : selected
                ? BmColors.gold
                : BmColors.violet.withValues(alpha: 0.75);

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: selected || correct
                    ? [
                        accent.withValues(alpha: 0.45),
                        accent.withValues(alpha: 0.18)
                      ]
                    : [
                        const Color(0xFF1A1C40).withValues(alpha: 0.92),
                        const Color(0xFF12142F).withValues(alpha: 0.92),
                      ],
              ),
              border: Border.all(
                color: accent,
                width: selected || correct || wrong ? 2 : 1.2,
              ),
              boxShadow: selected || correct
                  ? bmGlow(accent, blur: 18, opacity: 0.45)
                  : null,
            ),
            child: Row(
              children: [
                Text(
                  '$letter.',
                  style: BmText.title(14, color: accent)
                      .copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: BmText.body(14, color: Colors.white),
                  ),
                ),
                if (correct)
                  const Icon(Icons.check_circle,
                      color: BmColors.green, size: 18)
                else if (wrong)
                  const Icon(Icons.cancel, color: BmColors.red, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
