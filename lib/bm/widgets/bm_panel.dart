import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';

/// Frosted glass panel with a neon edge and a soft top sheen, used for the
/// question display and every secondary information block.
class BmPanel extends StatelessWidget {
  const BmPanel({
    super.key,
    required this.child,
    this.color = BmColors.violet,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 18,
    this.fillOpacity = 0.9,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final double borderRadius;
  final double fillOpacity;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A2160).withValues(alpha: fillOpacity * 0.82),
            const Color(0xFF0A0F30).withValues(alpha: fillOpacity * 0.92),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: color.withValues(alpha: 0.20),
            blurRadius: 22,
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
      ),
      padding: padding,
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
        borderRadius: BorderRadius.circular(12),
        gradient: BmGradients.panel,
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1.3),
        boxShadow: bmGlow(color, blur: 16, opacity: 0.35),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ROUND $round', style: BmText.label(10, color: color)),
          Text(title.toUpperCase(), style: BmText.display(15)),
        ],
      ),
    );
  }
}

/// Small rounded status pill (category, difficulty, LIVE, VIP...).
class BmChip extends StatelessWidget {
  const BmChip({
    super.key,
    required this.text,
    this.color = BmColors.cyan,
    this.icon,
    this.filled = false,
  });

  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: filled ? 0.9 : 0.14),
        border: Border.all(color: color.withValues(alpha: 0.75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: filled ? BmColors.deep : color),
            const SizedBox(width: 4),
          ],
          Text(
            text.toUpperCase(),
            style: BmText.label(9,
                color: filled ? BmColors.deep : color, spacing: 1.2),
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
        : progress > 0.25
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
            style: BmText.display(size * 0.4, color: Colors.white),
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
    final radius = size.width / 2 - 4;

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFF0A0F30).withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white.withValues(alpha: 0.10),
    );
    final arc = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      arc,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawArc(
      arc,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Answer option tile (A/B/C/D) with selected and revealed states.
///
/// A correct reveal pulses a green glow; a wrong pick shakes once.
class AnswerTile extends StatefulWidget {
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
  State<AnswerTile> createState() => _AnswerTileState();
}

class _AnswerTileState extends State<AnswerTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fx = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  bool _pressed = false;

  @override
  void didUpdateWidget(AnswerTile old) {
    super.didUpdateWidget(old);
    if ((widget.wrong && !old.wrong) || (widget.correct && !old.correct)) {
      _fx.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final accent = w.correct
        ? BmColors.green
        : w.wrong
            ? BmColors.red
            : w.selected
                ? BmColors.gold
                : BmColors.violet;
    final lit = w.selected || w.correct || w.wrong;

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: lit
              ? [
                  accent.withValues(alpha: 0.42),
                  accent.withValues(alpha: 0.12),
                ]
              : [
                  const Color(0xFF1B2366).withValues(alpha: 0.92),
                  const Color(0xFF0D1238).withValues(alpha: 0.92),
                ],
        ),
        border: Border.all(
          color: lit ? accent : BmColors.violet.withValues(alpha: 0.55),
          width: lit ? 2 : 1.2,
        ),
        boxShadow: lit ? bmGlow(accent, blur: 20, opacity: 0.5) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: lit ? accent : BmColors.violet.withValues(alpha: 0.25),
              border: Border.all(color: accent.withValues(alpha: 0.9)),
            ),
            child: Text(
              w.letter,
              style: BmText.display(
                15,
                color: lit ? BmColors.deep : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              w.text,
              style: BmText.body(14.5, color: Colors.white),
            ),
          ),
          if (w.correct)
            const Icon(Icons.check_circle_rounded,
                color: BmColors.green, size: 22)
          else if (w.wrong)
            const Icon(Icons.cancel_rounded, color: BmColors.red, size: 22),
        ],
      ),
    );

    return AnimatedBuilder(
      animation: _fx,
      builder: (context, child) {
        final t = _fx.value;
        final dx = w.wrong ? math.sin(t * math.pi * 6) * 9 * (1 - t) : 0.0;
        final scale = w.correct ? 1 + math.sin(t * math.pi) * 0.04 : 1.0;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Opacity(
        opacity: w.enabled || lit ? 1 : 0.55,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: w.enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: w.enabled ? w.onTap : null,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: const Duration(milliseconds: 90),
            child: tile,
          ),
        ),
      ),
    );
  }
}
