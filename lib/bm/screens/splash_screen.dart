import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import '../player/player_profile.dart';
import '../settings/bm_audio_settings.dart';
import '../widgets/studio_background.dart';

/// Animated splash: the logo powers up inside a spinning neon ring while the
/// player's saved settings and profile load, then hands over to [next].
class BmSplashScreen extends StatefulWidget {
  const BmSplashScreen({super.key, required this.next});

  final Widget next;

  @override
  State<BmSplashScreen> createState() => _BmSplashScreenState();
}

class _BmSplashScreenState extends State<BmSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _left = false;

  @override
  void initState() {
    super.initState();
    final loading = Future.wait([
      BmAudioSettings.ensureLoaded(),
      PlayerProfileStore.ensureLoaded(),
    ]).catchError((Object _) => <void>[]);
    _c.forward().whenComplete(() async {
      await loading.timeout(const Duration(seconds: 2), onTimeout: () => []);
      _leave();
    });
  }

  void _leave() {
    if (!mounted || _left) return;
    _left = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _leave,
      child: StudioScaffold(
        intensity: 0.9,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final logoIn =
                Curves.easeOutBack.transform((t / 0.45).clamp(0.0, 1.0));
            final textIn =
                Curves.easeOut.transform(((t - 0.4) / 0.3).clamp(0.0, 1.0));
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 300,
                    height: 300,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(290, 290),
                          painter: _RingPainter(t),
                        ),
                        Opacity(
                          opacity: logoIn.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.5 + 0.5 * logoIn,
                            child: Image.asset('assets/images/bm_logo.png',
                                width: 230),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Opacity(
                    opacity: textIn,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - textIn)),
                      child: Column(
                        children: [
                          Text('NEON TURBO QUIZ ARENA',
                              style: BmText.display(18, color: BmColors.cyan)
                                  .copyWith(letterSpacing: 5)),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: 180,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: t,
                                minHeight: 4,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.1),
                                valueColor:
                                    const AlwaysStoppedAnimation(BmColors.gold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('WARMING UP THE ENGINES',
                              style: BmText.label(9)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    final sweep = math.pi * 2 * Curves.easeInOut.transform(t);
    final rect = Rect.fromCircle(center: c, radius: r);
    for (final (color, start, width) in [
      (BmColors.cyan, -math.pi / 2, 3.0),
      (BmColors.purple, math.pi / 2, 3.0),
    ]) {
      canvas.drawArc(
        rect,
        start + t * math.pi,
        sweep * 0.5,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width + 8
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawArc(
        rect,
        start + t * math.pi,
        sweep * 0.5,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
    canvas.drawCircle(
      c,
      r - 16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = BmColors.gold.withValues(alpha: 0.35 * t),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t;
}
