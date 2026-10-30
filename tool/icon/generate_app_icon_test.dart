// Renders the Buzz Masters app icon (1024 x 1024, opaque) to
// tool/icon/app_icon_1024.png. Run with:
//   flutter test tool/icon/generate_app_icon_test.dart
// then tool/icon/apply_icons.sh to produce every platform size.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _deep = Color(0xFF060825);
const _purple = Color(0xFFB24DFF);
const _cyan = Color(0xFF22E6FF);
const _pink = Color(0xFFFF3DAE);
const _gold = Color(0xFFFFC94A);

void paintIcon(Canvas c, double s) {
  final full = Rect.fromLTWH(0, 0, s, s);
  // Midnight-to-ultraviolet stadium glow.
  c.drawRect(
    full,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.25),
        radius: 0.95,
        colors: [Color(0xFF3A16A0), Color(0xFF170B55), _deep],
        stops: [0, 0.5, 1],
      ).createShader(full),
  );

  // Converging neon race lanes.
  final vp = Offset(s * 0.5, s * 0.40);
  final lanes = [_cyan, _purple, _gold, _purple, _pink];
  for (var i = 0; i < lanes.length; i++) {
    final x = s * (-0.15 + i * 0.325);
    final glow = Paint()
      ..color = lanes[i].withValues(alpha: 0.35)
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.02);
    final line = Paint()
      ..color = lanes[i]
      ..strokeWidth = s * 0.014
      ..strokeCap = StrokeCap.round;
    c.drawLine(vp, Offset(x, s * 1.05), glow);
    c.drawLine(vp, Offset(x, s * 1.05), line);
  }
  // Chevrons streaming down the track.
  for (var k = 0; k < 3; k++) {
    final t = 0.45 + k * 0.2;
    final y = vp.dy + (s - vp.dy) * t;
    final half = s * 0.10 * t * 1.6;
    final p = Path()
      ..moveTo(s * 0.5 - half, y + half * 0.45)
      ..lineTo(s * 0.5, y)
      ..lineTo(s * 0.5 + half, y + half * 0.45);
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.018 * t
        ..strokeCap = StrokeCap.round
        ..color = _cyan.withValues(alpha: 0.25 + 0.35 * t),
    );
  }

  // Gold lighting halo.
  final halo = Rect.fromCenter(
      center: Offset(s * 0.5, s * 0.43), width: s * 0.70, height: s * 0.70);
  c.drawOval(
    halo,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05
      ..color = _gold.withValues(alpha: 0.25)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
  );
  c.drawOval(
    halo,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.016
      ..shader = const SweepGradient(
        colors: [_gold, Color(0xFFFFF0B3), _gold, Color(0xFFE08A1E), _gold],
      ).createShader(halo),
  );
  for (var i = 0; i < 16; i++) {
    final a = i / 16 * math.pi * 2;
    c.drawCircle(
      halo.center + Offset(math.cos(a), math.sin(a)) * (halo.width / 2),
      s * 0.008,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  // The buzz: a bold lightning bolt.
  final b = Path()
    ..moveTo(s * 0.575, s * 0.17)
    ..lineTo(s * 0.33, s * 0.49)
    ..lineTo(s * 0.475, s * 0.49)
    ..lineTo(s * 0.405, s * 0.72)
    ..lineTo(s * 0.67, s * 0.37)
    ..lineTo(s * 0.52, s * 0.37)
    ..close();
  c.drawPath(
    b.shift(Offset(0, s * 0.012)),
    Paint()
      ..color = _gold.withValues(alpha: 0.75)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.045),
  );
  c.drawPath(
    b,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFF6CC), _gold, Color(0xFFE0781E)],
      ).createShader(b.getBounds()),
  );
  c.drawPath(
    b,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.008
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.85),
  );
  // Vignette.
  c.drawRect(
    full,
    Paint()
      ..shader = RadialGradient(
        radius: 0.9,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.35)],
        stops: const [0.7, 1],
      ).createShader(full),
  );
}

void main() {
  testWidgets('render app icon', (tester) async {
    await tester.runAsync(() async {
      const size = 1024.0;
      final rec = ui.PictureRecorder();
      paintIcon(Canvas(rec), size);
      final img = await rec.endRecording().toImage(1024, 1024);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('tool/icon/app_icon_1024.png')
          .writeAsBytesSync(png!.buffer.asUint8List());
    });
    expect(File('tool/icon/app_icon_1024.png').existsSync(), isTrue);
  });
}
