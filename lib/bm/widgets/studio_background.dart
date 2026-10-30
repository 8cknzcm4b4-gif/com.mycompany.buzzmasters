import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';

/// Painted neon quiz arena: ultraviolet stadium glow, a gold lighting halo,
/// twinkling crowd tiers, sweeping spotlights and a glossy perspective runway.
/// Drawn with a CustomPainter so it stays crisp at any size and needs no
/// image assets.
class StudioBackground extends StatefulWidget {
  const StudioBackground({
    super.key,
    this.showAudience = true,
    this.showFloor = true,
    this.animated = true,
    this.intensity = 0.5,
    this.child,
  });

  final bool showAudience;
  final bool showFloor;
  final bool animated;

  /// 0 to 1: how lit the arena is. Races raise it as the leader nears the
  /// finish, so the whole stadium builds with the race.
  final double intensity;
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
      duration: const Duration(seconds: 10),
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
        painter: ArenaPainter(
          phase: _controller.value,
          showAudience: widget.showAudience,
          showFloor: widget.showFloor,
          intensity: widget.intensity,
        ),
        child: child,
      ),
      child: RepaintBoundary(child: widget.child),
    );
  }
}

class ArenaPainter extends CustomPainter {
  ArenaPainter({
    required this.phase,
    required this.showAudience,
    required this.showFloor,
    this.intensity = 0.5,
  });

  final double phase;
  final bool showAudience;
  final bool showFloor;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final full = Offset.zero & size;
    final lift = 0.7 + intensity * 0.6;

    canvas.drawRect(
      full,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E0838), BmColors.midnight, BmColors.deep],
          stops: [0.0, 0.5, 1.0],
        ).createShader(full),
    );

    _glow(canvas, Offset(w * 0.5, h * 0.22), w * 0.95,
        BmColors.violet.withValues(alpha: 0.38 * lift));
    _glow(canvas, Offset(w * 0.5, h * 0.18), w * 0.42,
        BmColors.purple.withValues(alpha: 0.22 * lift));
    _glow(canvas, Offset(-w * 0.05, h * 0.42), w * 0.6,
        BmColors.cyan.withValues(alpha: 0.13 * lift));
    _glow(canvas, Offset(w * 1.05, h * 0.42), w * 0.6,
        BmColors.pink.withValues(alpha: 0.12 * lift));

    _halo(canvas, w, h);
    _beams(canvas, w, h);
    if (showAudience) _crowd(canvas, w, h);
    if (showFloor) _floor(canvas, w, h);

    // Vignette keeps the eye in the centre and the edges calm.
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          radius: 1.05,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
          stops: const [0.6, 1.0],
        ).createShader(full),
    );
  }

  /// The suspended gold lighting ring above the arena.
  void _halo(Canvas canvas, double w, double h) {
    final rect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.035),
      width: w * 1.25,
      height: h * 0.11,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = BmColors.gold.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = BmColors.gold.withValues(alpha: 0.45),
    );
    for (var i = 0; i < 22; i++) {
      final a = math.pi * (i + 0.5) / 22;
      final p = Offset(
        rect.center.dx - math.cos(a) * rect.width / 2,
        rect.center.dy + math.sin(a) * rect.height / 2,
      );
      final pulse = 0.5 + 0.5 * math.sin(phase * math.pi * 4 + i * 0.9);
      canvas.drawCircle(
        p,
        2.2,
        Paint()..color = Colors.white.withValues(alpha: 0.35 + 0.5 * pulse),
      );
      canvas.drawCircle(
        p,
        7,
        Paint()..color = BmColors.gold.withValues(alpha: 0.10 * pulse),
      );
    }
  }

  void _beams(Canvas canvas, double w, double h) {
    for (var i = 0; i < 5; i++) {
      final sway = math.sin(phase * math.pi * 2 + i * 1.7) * w * 0.10;
      final originX = w * (0.1 + i * 0.2);
      final spread = w * 0.09;
      final beam = Path()
        ..moveTo(originX - 3, h * 0.03)
        ..lineTo(originX + 3, h * 0.03)
        ..lineTo(originX + sway + spread, h * 0.62)
        ..lineTo(originX + sway - spread, h * 0.62)
        ..close();
      final color = switch (i % 3) {
        0 => BmColors.cyan,
        1 => BmColors.purple,
        _ => Colors.white,
      };
      canvas.drawPath(
        beam,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.13 + intensity * 0.08),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, w, h * 0.62)),
      );
    }
  }

  /// Curved stadium tiers dotted with phone lights and wristbands.
  void _crowd(Canvas canvas, double w, double h) {
    final rng = math.Random(11);
    for (var tier = 0; tier < 4; tier++) {
      final cy = h * (0.20 + tier * 0.045);
      final sag = h * (0.035 + tier * 0.01);
      final count = 34 + tier * 6;
      for (var i = 0; i < count; i++) {
        final t = (i + rng.nextDouble() * 0.6) / count;
        final x = w * (t * 1.2 - 0.1);
        final y = cy + sag * (1 - math.pow((t - 0.5) * 2, 2).toDouble());
        final seed = rng.nextDouble();
        final twinkle =
            0.5 + 0.5 * math.sin(phase * math.pi * 2 * 3 + seed * 20);
        final color = switch ((seed * 5).floor()) {
          0 => BmColors.cyan,
          1 => BmColors.pink,
          2 => BmColors.gold,
          _ => BmColors.purple,
        };
        canvas.drawCircle(
          Offset(x, y),
          1.1 + tier * 0.25,
          Paint()
            ..color = color.withValues(
              alpha: (0.25 + 0.55 * twinkle) * (0.6 + intensity * 0.5),
            ),
        );
      }
      // Tier rail.
      final rail = Path()
        ..moveTo(-w * 0.1, cy + 8)
        ..quadraticBezierTo(w * 0.5, cy + sag * 2 + 8, w * 1.1, cy + 8);
      canvas.drawPath(
        rail,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = (tier.isEven ? BmColors.violet : BmColors.cyan)
              .withValues(alpha: 0.25),
      );
    }
  }

  /// Glossy perspective runway with neon edge rails and gold chevrons that
  /// stream towards the viewer.
  void _floor(Canvas canvas, double w, double h) {
    final horizon = h * 0.60;
    final vp = Offset(w * 0.5, horizon);
    final floorRect = Rect.fromLTWH(0, horizon, w, h - horizon);
    canvas.drawRect(
      floorRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF100B34), Color(0xFF050720)],
        ).createShader(floorRect),
    );
    _glow(canvas, vp, w * 0.7, BmColors.violet.withValues(alpha: 0.30));
    _glow(canvas, vp, w * 0.3, BmColors.cyan.withValues(alpha: 0.16));

    // Converging grid lines.
    final grid = Paint()..strokeWidth = 1;
    for (var i = -8; i <= 8; i++) {
      final x = w * 0.5 + i * w * 0.16;
      grid.color =
          (i.isEven ? BmColors.violet : BmColors.cyan).withValues(alpha: 0.16);
      canvas.drawLine(vp, Offset(x + i * w * 0.25, h), grid);
    }
    // Horizontal grid lines streaming towards the viewer.
    for (var k = 0; k < 9; k++) {
      final t = ((k + phase * 3) % 9) / 9;
      final y = horizon + (h - horizon) * t * t;
      grid.color = BmColors.violet.withValues(alpha: 0.05 + 0.20 * t);
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }

    // Runway edge rails.
    final rail = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (final side in [-1.0, 1.0]) {
      final base = Offset(w * 0.5 + side * w * 0.30, h);
      rail
        ..color = BmColors.gold.withValues(alpha: 0.12)
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawLine(vp, base, rail);
      rail
        ..color = BmColors.gold.withValues(alpha: 0.55)
        ..strokeWidth = 1.6
        ..maskFilter = null;
      canvas.drawLine(vp, base, rail);
    }

    // Chevrons.
    for (var k = 0; k < 4; k++) {
      final t = ((k + phase * 2) % 4) / 4;
      final y = horizon + (h - horizon) * t * t;
      final half = w * 0.30 * t * 0.55;
      final depth = (h - horizon) * 0.05 * t;
      final chevron = Path()
        ..moveTo(w * 0.5 - half, y + depth)
        ..lineTo(w * 0.5, y)
        ..lineTo(w * 0.5 + half, y + depth);
      canvas.drawPath(
        chevron,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 + 4 * t
          ..strokeCap = StrokeCap.round
          ..color = BmColors.cyan.withValues(alpha: 0.10 + 0.35 * t),
      );
    }
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
  bool shouldRepaint(covariant ArenaPainter old) =>
      old.phase != phase ||
      old.showAudience != showAudience ||
      old.showFloor != showFloor ||
      old.intensity != intensity;
}

/// Convenience scaffold: full-bleed animated arena with safe-area content.
class StudioScaffold extends StatelessWidget {
  const StudioScaffold({
    super.key,
    required this.child,
    this.showAudience = true,
    this.showFloor = true,
    this.padding = const EdgeInsets.all(20),
    this.safeArea = true,
    this.intensity = 0.5,
  });

  final Widget child;
  final bool showAudience;
  final bool showFloor;
  final EdgeInsets padding;
  final bool safeArea;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BmColors.deep,
      body: StudioBackground(
        showAudience: showAudience,
        showFloor: showFloor,
        intensity: intensity,
        child: SafeArea(
          top: safeArea,
          bottom: safeArea,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
