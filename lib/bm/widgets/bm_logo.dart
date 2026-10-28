import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/bm_theme.dart';

/// Original Buzz Masters wordmark: gold "BUZZ" over chrome-blue "MASTERS",
/// crowned, with the official tagline. Scales to any width without assets.
class BmLogo extends StatelessWidget {
  const BmLogo({super.key, this.width = 320, this.showTagline = true});

  final double width;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final word = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 34,
          width: 62,
          child: CustomPaint(painter: _CrownPainter()),
        ),
        _LogoWord(text: 'BUZZ', size: 74, gradient: BmGradients.gold),
        Transform.translate(
          offset: const Offset(0, -8),
          child: _LogoWord(
            text: 'MASTERS',
            size: 62,
            gradient: BmGradients.silver,
          ),
        ),
      ],
    );

    return SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _Bolt(color: BmColors.cyan, size: 30),
                const SizedBox(width: 6),
                word,
                const SizedBox(width: 6),
                const _Bolt(color: BmColors.gold, size: 30),
              ],
            ),
            if (showTagline) ...[
              const SizedBox(height: 6),
              Text(
                'SIX PLAYERS. THREE ROUNDS. ONE MASTER.',
                style: BmText.label(11.5, color: Colors.white, spacing: 2.0),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogoWord extends StatelessWidget {
  const _LogoWord({
    required this.text,
    required this.size,
    required this.gradient,
  });

  final String text;
  final double size;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.poppins(
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 0.92,
      letterSpacing: -2.5,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.14
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xFF1A0B33),
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => gradient.createShader(rect),
          child: Text(text, style: base.copyWith(color: Colors.white)),
        ),
      ],
    );
  }
}

class _Bolt extends StatelessWidget {
  const _Bolt({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.6,
      child: CustomPaint(painter: _BoltPainter(color)),
    );
  }
}

class _BoltPainter extends CustomPainter {
  _BoltPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width * 0.62, 0)
      ..lineTo(size.width * 0.10, size.height * 0.56)
      ..lineTo(size.width * 0.44, size.height * 0.56)
      ..lineTo(size.width * 0.30, size.height)
      ..lineTo(size.width * 0.92, size.height * 0.40)
      ..lineTo(size.width * 0.55, size.height * 0.40)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, color, color.withValues(alpha: 0.5)],
        ).createShader(Offset.zero & size)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
  }

  @override
  bool shouldRepaint(covariant _BoltPainter old) => old.color != color;
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final crown = Path()
      ..moveTo(0, h)
      ..lineTo(w * 0.06, h * 0.18)
      ..lineTo(w * 0.28, h * 0.62)
      ..lineTo(w * 0.50, h * 0.02)
      ..lineTo(w * 0.72, h * 0.62)
      ..lineTo(w * 0.94, h * 0.18)
      ..lineTo(w, h)
      ..close();

    final paint = Paint()
      ..shader = BmGradients.gold.createShader(Offset.zero & size)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.4);
    canvas.drawPath(crown, paint);

    final jewel = Paint()..color = const Color(0xFFFF4E87);
    canvas.drawCircle(Offset(w * 0.25, h * 0.82), w * 0.045, jewel);
    canvas.drawCircle(Offset(w * 0.50, h * 0.80), w * 0.05, jewel);
    canvas.drawCircle(Offset(w * 0.75, h * 0.82), w * 0.045, jewel);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
