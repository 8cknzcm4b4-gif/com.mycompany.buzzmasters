import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';

/// Painted 3D quiz-show studio: back-lit cyclorama, lighting rig, audience and
/// a reflective stage floor. Drawn with a CustomPainter so it stays crisp at
/// any size and needs no image assets.
class StudioBackground extends StatefulWidget {
  const StudioBackground({
    super.key,
    this.showAudience = true,
    this.showFloor = true,
    this.animated = true,
    this.child,
  });

  final bool showAudience;
  final bool showFloor;
  final bool animated;
  final Widget? child;

  @override
  State<StudioBackground> createState() => _StudioBackgroundState();
}

class _StudioBackgroundState extends State<StudioBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (widget.animated) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => CustomPaint(
        painter: _StudioPainter(
          phase: _controller.value,
          showAudience: widget.showAudience,
          showFloor: widget.showFloor,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _StudioPainter extends CustomPainter {
  _StudioPainter({
    required this.phase,
    required this.showAudience,
    required this.showFloor,
  });

  final double phase;
  final bool showAudience;
  final bool showFloor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final full = Rect.fromLTWH(0, 0, w, h);

    // Deep studio backdrop.
    canvas.drawRect(
      full,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2E1668), BmColors.midnight, BmColors.deep],
          stops: [0.0, 0.55, 1.0],
        ).createShader(full),
    );

    // Ambient colour wash.
    _glow(canvas, Offset(w * 0.5, h * 0.40), w * 0.85,
        BmColors.violet.withValues(alpha: 0.45));
    _glow(canvas, Offset(w * 0.5, h * 0.55), w * 0.40,
        BmColors.pink.withValues(alpha: 0.18));
    _glow(canvas, Offset(w * 0.08, h * 0.30), w * 0.45,
        BmColors.cyan.withValues(alpha: 0.16));
    _glow(canvas, Offset(w * 0.92, h * 0.30), w * 0.45,
        BmColors.pink.withValues(alpha: 0.18));

    // Vertical LED strips on the cyclorama.
    final strip = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 14; i++) {
      final x = w * (i + 0.5) / 14;
      final pulse = 0.5 + 0.5 * math.sin(phase * math.pi * 2 + i * 0.7);
      strip
        ..color = (i.isEven ? BmColors.violet : BmColors.cyan)
            .withValues(alpha: 0.10 + pulse * 0.24)
        ..strokeWidth = 3;
      canvas.drawLine(Offset(x, h * 0.06), Offset(x, h * 0.52), strip);
    }

    // Overhead lighting rig.
    final rig = Rect.fromLTWH(0, 0, w, h * 0.10);
    canvas.drawRect(
      rig,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
        ).createShader(rig),
    );

    // Moving spotlight beams.
    for (var i = 0; i < 6; i++) {
      final sway = math.sin(phase * math.pi * 2 + i * 1.3) * w * 0.03;
      final originX = w * (i + 0.5) / 6;
      final beam = Path()
        ..moveTo(originX - 6, 0)
        ..lineTo(originX + 6, 0)
        ..lineTo(originX + sway + w * 0.13, h * 0.75)
        ..lineTo(originX + sway - w * 0.13, h * 0.75)
        ..close();
      final color = i.isEven
          ? BmColors.gold.withValues(alpha: 0.10)
          : BmColors.cyan.withValues(alpha: 0.08);
      canvas.drawPath(
        beam,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, Colors.transparent],
          ).createShader(Rect.fromLTWH(0, 0, w, h * 0.75)),
      );
    }

    // Fixture bulbs along the rig.
    for (var i = 0; i < 18; i++) {
      final x = w * (i + 0.5) / 18;
      final pulse = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(phase * math.pi * 2 + i));
      canvas.drawCircle(
        Offset(x, h * 0.035),
        5.5,
        Paint()..color = BmColors.gold.withValues(alpha: 0.25 + pulse * 0.45),
      );
      canvas.drawCircle(
        Offset(x, h * 0.035),
        11,
        Paint()..color = BmColors.gold.withValues(alpha: 0.06 * pulse),
      );
    }

    if (showAudience) _audience(canvas, w, h);

    if (showFloor) _floor(canvas, w, h);
  }

  void _audience(Canvas canvas, double w, double h) {
    final top = h * 0.34;
    for (var row = 0; row < 4; row++) {
      final y = top + row * h * 0.05;
      for (var i = 0; i < 26; i++) {
        final x = w * (i + (row.isEven ? 0.5 : 1.0)) / 26;
        final d = 0.34 - row * 0.055;
        canvas.drawCircle(
          Offset(x, y),
          8.0 - row * 0.8,
          Paint()..color = BmColors.violet.withValues(alpha: d * 0.55),
        );
        canvas.drawCircle(
          Offset(x, y),
          7.0 - row * 0.8,
          Paint()..color = const Color(0xFF07040F).withValues(alpha: d),
        );
        canvas.drawCircle(
          Offset(x, y - 12),
          4.2,
          Paint()..color = BmColors.cyan.withValues(alpha: d * 0.4),
        );
        canvas.drawCircle(
          Offset(x, y - 12),
          3.6,
          Paint()..color = const Color(0xFF07040F).withValues(alpha: d),
        );
      }
    }
  }

  void _floor(Canvas canvas, double w, double h) {
    final horizon = h * 0.68;
    final floorRect = Rect.fromLTWH(0, horizon, w, h - horizon);
    canvas.drawRect(
      floorRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF14102B), Color(0xFF0A0818)],
        ).createShader(floorRect),
    );

    // Glossy reflection band at the horizon.
    _glow(canvas, Offset(w * 0.5, horizon), w * 0.55,
        BmColors.violet.withValues(alpha: 0.35));
    _glow(canvas, Offset(w * 0.5, horizon), w * 0.30,
        BmColors.cyan.withValues(alpha: 0.18));

    // Golden emblem pool at centre stage.
    final emblem = Path()
      ..moveTo(w * 0.5 - w * 0.10, h)
      ..lineTo(w * 0.5 + w * 0.10, h)
      ..lineTo(w * 0.5 + w * 0.26, horizon + h * 0.02)
      ..lineTo(w * 0.5 - w * 0.26, horizon + h * 0.02)
      ..close();
    canvas.drawPath(
      emblem,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BmColors.gold.withValues(alpha: 0.0),
            BmColors.gold.withValues(alpha: 0.16),
          ],
        ).createShader(Rect.fromLTWH(0, horizon, w, h - horizon)),
    );

    // Concentric stage rings, foreshortened into ellipses.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    for (var i = 0; i < 5; i++) {
      final t = i / 4;
      final rect = Rect.fromCenter(
        center: Offset(w * 0.5, h * (0.86 + i * 0.03)),
        width: w * (0.30 + t * 0.85),
        height: h * (0.05 + t * 0.10),
      );
      ring.color = (i.isEven ? BmColors.gold : BmColors.violet)
          .withOpacity(0.28 - i * 0.04);
      canvas.drawOval(rect, ring);
    }

    // Reflective sheen.
    final sheen = Rect.fromLTWH(0, horizon, w, h * 0.10);
    canvas.drawRect(
      sheen,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BmColors.cyan.withValues(alpha: 0.10),
            Colors.transparent,
          ],
        ).createShader(sheen),
    );
  }

  void _glow(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(covariant _StudioPainter old) =>
      old.phase != phase ||
      old.showAudience != showAudience ||
      old.showFloor != showFloor;
}

/// Convenience scaffold: full-bleed animated studio with safe-area content.
class StudioScaffold extends StatelessWidget {
  const StudioScaffold({
    super.key,
    required this.child,
    this.showAudience = true,
    this.showFloor = true,
    this.padding = const EdgeInsets.all(20),
    this.safeArea = true,
  });

  final Widget child;
  final bool showAudience;
  final bool showFloor;
  final EdgeInsets padding;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BmColors.deep,
      body: StudioBackground(
        showAudience: showAudience,
        showFloor: showFloor,
        child: SafeArea(
          top: safeArea,
          bottom: safeArea,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
