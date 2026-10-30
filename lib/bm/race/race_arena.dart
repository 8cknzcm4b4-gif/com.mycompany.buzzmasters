import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../design/bm_theme.dart';
import 'race_model.dart';

/// One racer as the arena draws them. Built from confirmed [RaceModel] state;
/// the arena never moves a racer on its own.
@immutable
class ArenaRacer {
  const ArenaRacer({
    required this.id,
    required this.name,
    required this.color,
    required this.progress,
    required this.speed,
    this.finished = false,
    this.eliminated = false,
    this.danger = false,
    this.isPlayer = false,
  });

  final String id;
  final String name;
  final Color color;
  final int progress;
  final SpeedStatus speed;
  final bool finished;
  final bool eliminated;
  final bool danger;
  final bool isPlayer;
}

/// The televised race: a six-lane perspective neon track with racing pods
/// placed by each racer's confirmed progress, a live standings board, score
/// pops, overtake call-outs, a final-stretch build-up and a finish flash.
class RaceArena extends StatefulWidget {
  const RaceArena({
    super.key,
    required this.racers,
    required this.distance,
    required this.positions,
    this.running = false,
    this.finished = false,
    this.overlay,
    this.hudLabel,
    this.onPlayerOvertake,
    this.showStandings = true,
  });

  /// Hides the position board, for small decorative previews.
  final bool showStandings;

  /// Racers in lane order (lane 1 first).
  final List<ArenaRacer> racers;
  final int distance;

  /// Race position per racer id; empty before the start.
  final Map<String, int> positions;

  /// Whether the race clock is running, which drives the track scroll.
  final bool running;

  /// The race is over: shows the finish flash.
  final bool finished;

  /// Drawn above the track, centred (the start countdown).
  final Widget? overlay;

  /// Top-left HUD text such as `Q 4 / 30`.
  final String? hudLabel;

  /// Called when the player moves up at least one place.
  final VoidCallback? onPlayerOvertake;

  @override
  State<RaceArena> createState() => _RaceArenaState();
}

class _RaceArenaState extends State<RaceArena>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _scene = _ArenaScene();
  Duration _last = Duration.zero;
  String? _callout;
  Timer? _calloutTimer;

  @override
  void initState() {
    super.initState();
    _sync();
    for (final r in widget.racers) {
      _scene.display[r.id] = r.progress.toDouble();
    }
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(RaceArena old) {
    super.didUpdateWidget(old);
    final before = {for (final r in old.racers) r.id: r};
    for (final r in widget.racers) {
      final prev = before[r.id];
      if (prev == null) continue;
      final delta = r.progress - prev.progress;
      if (delta != 0 && widget.showStandings) {
        _scene.addFx(r.id, delta > 0 ? '+$delta' : '$delta',
            delta > 0 ? BmColors.green : BmColors.red);
      }
      if (r.eliminated && !prev.eliminated) {
        _scene.addFx(r.id, 'OUT', BmColors.red);
      }
      final was = old.positions[r.id] ?? 0;
      final now = widget.positions[r.id] ?? 0;
      if (was > 0 && now > 0 && now < was && !r.finished) {
        _scene.addFx(r.id, '▲ P$now', BmColors.gold, lift: 18);
        if (r.isPlayer) _showCallout('OVERTAKE!  P$now');
      }
    }
    _sync();
  }

  void _showCallout(String text) {
    widget.onPlayerOvertake?.call();
    _calloutTimer?.cancel();
    setState(() => _callout = text);
    _calloutTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _callout = null);
    });
  }

  void _sync() {
    _scene
      ..racers = widget.racers
      ..positions = widget.positions
      ..distance = widget.distance
      ..finished = widget.finished;
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    _scene.time = elapsed.inMicroseconds / 1e6;
    final pace = widget.finished
        ? 0.3
        : widget.running
            ? (_scene.finalStretch ? 1.9 : 1.0)
            : 0.0;
    _scene.pace += (pace - _scene.pace) * (1 - math.exp(-dt * 3));
    _scene.scroll += dt * _scene.pace;
    final ease = 1 - math.exp(-dt * 4.5);
    for (final r in widget.racers) {
      final d = _scene.display[r.id] ?? r.progress.toDouble();
      _scene.display[r.id] = d + (r.progress - d) * ease;
    }
    _scene.fx.removeWhere((f) => _scene.time - f.start > 1.3);
    _scene.tick();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _calloutTimer?.cancel();
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leader = widget.racers.isEmpty
        ? 0
        : widget.racers.map((r) => r.progress).reduce(math.max);
    final stretch =
        !widget.finished && widget.running && leader >= widget.distance * 0.75;
    _scene.finalStretch = stretch;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: BmColors.violet.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(painter: _TrackPainter(_scene)),
            ),
            if (widget.showStandings)
              Positioned(
                top: 8,
                right: 8,
                child: _Standings(
                  racers: widget.racers,
                  positions: widget.positions,
                  distance: widget.distance,
                ),
              ),
            if (widget.hudLabel != null)
              Positioned(
                top: 8,
                left: 8,
                child: _Hud(
                  label: widget.hudLabel!,
                  player: widget.racers
                      .where((r) => r.isPlayer)
                      .cast<ArenaRacer?>()
                      .firstWhere((_) => true, orElse: () => null),
                ),
              ),
            if (stretch)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(child: _Banner('FINAL STRETCH')),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, a) => ScaleTransition(
                      scale: Tween(begin: 0.6, end: 1.0).animate(
                          CurvedAnimation(
                              parent: a, curve: Curves.easeOutBack)),
                      child: FadeTransition(opacity: a, child: child),
                    ),
                    child: widget.finished
                        ? const _FinishFlash(key: ValueKey('finish'))
                        : _callout != null
                            ? _Banner(_callout!, key: ValueKey(_callout))
                            : widget.overlay ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fx {
  _Fx(this.id, this.text, this.color, this.start, this.lift);
  final String id;
  final String text;
  final Color color;
  final double start;
  final double lift;
}

/// Mutable per-frame state shared between the ticker and the painter.
class _ArenaScene extends ChangeNotifier {
  List<ArenaRacer> racers = const [];
  Map<String, int> positions = const {};
  int distance = 100;
  bool finished = false;
  bool finalStretch = false;
  double time = 0;
  double scroll = 0;
  double pace = 0;
  final Map<String, double> display = {};
  final List<_Fx> fx = [];

  void addFx(String id, String text, Color color, {double lift = 0}) =>
      fx.add(_Fx(id, text, color, time, lift));

  void tick() => notifyListeners();
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.s) : super(repaint: s);

  final _ArenaScene s;

  // World depths: 1 is at the camera; larger is further down the track.
  static const _dNear = 0.82;
  static const _dStart = 1.14;
  static const _dFinish = 3.0;
  static const _dFar = 5.0;

  late double _w;
  late double _h;
  late double _vpY;

  double _y(double d) => _vpY + (_h - _vpY) / d;
  double _half(double d) => _w * 0.47 / d;
  double _edge(double t, double d) => _w / 2 + (t - 0.5) * 2 * _half(d);

  double _depthFor(double progress) =>
      _dStart +
      (progress / math.max(1, s.distance)).clamp(0.0, 1.0) *
          (_dFinish - _dStart);

  @override
  void paint(Canvas canvas, Size size) {
    _w = size.width;
    _h = size.height;
    _vpY = _h * 0.05;
    final n = math.max(1, s.racers.length);

    _sky(canvas);
    _surface(canvas, n);
    _finishLine(canvas);
    _laneNumbers(canvas, n);

    final order = [
      for (var i = 0; i < s.racers.length; i++) i,
    ]..sort((a, b) => _depthFor(s.display[s.racers[b].id] ?? 0)
        .compareTo(_depthFor(s.display[s.racers[a].id] ?? 0)));
    for (final i in order) {
      _car(canvas, s.racers[i], i, n);
    }
    _effects(canvas, n);
  }

  void _sky(Canvas canvas) {
    final rect = Offset.zero & Size(_w, _h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xEE0D0838), Color(0xEE070A26)],
        ).createShader(rect),
    );
    // Trophy glow beyond the finish, brighter in the final stretch.
    final glowC = Offset(_w / 2, _y(_dFar));
    final strength = s.finalStretch ? 0.45 + 0.15 * math.sin(s.time * 6) : 0.22;
    canvas.drawCircle(
      glowC,
      _w * 0.45,
      Paint()
        ..shader = RadialGradient(colors: [
          BmColors.gold.withValues(alpha: strength),
          BmColors.violet.withValues(alpha: strength * 0.4),
          Colors.transparent,
        ], stops: const [
          0,
          0.4,
          1
        ]).createShader(Rect.fromCircle(center: glowC, radius: _w * 0.45)),
    );
    // Crowd lights along the top.
    final rng = math.Random(3);
    for (var i = 0; i < 60; i++) {
      final x = rng.nextDouble() * _w;
      final y = _vpY * 0.2 + rng.nextDouble() * (_y(_dFar) - _vpY * 0.2);
      final tw = 0.5 + 0.5 * math.sin(s.time * 4 + i);
      canvas.drawCircle(
        Offset(x, y),
        1.2,
        Paint()..color = BmSeat.colorFor(i).withValues(alpha: 0.2 + 0.5 * tw),
      );
    }
  }

  Path _band(double t0, double t1, double d0, double d1) => Path()
    ..moveTo(_edge(t0, d0), _y(d0))
    ..lineTo(_edge(t0, d1), _y(d1))
    ..lineTo(_edge(t1, d1), _y(d1))
    ..lineTo(_edge(t1, d0), _y(d0))
    ..close();

  void _surface(Canvas canvas, int n) {
    final track = _band(0, 1, _dNear, _dFar);
    canvas.drawPath(
      track,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1250), Color(0xFF0B0F33)],
        ).createShader(Rect.fromLTWH(0, _y(_dFar), _w, _h)),
    );

    // Lane tints, the player's lane a little brighter.
    for (var i = 0; i < s.racers.length; i++) {
      final r = s.racers[i];
      canvas.drawPath(
        _band(i / n, (i + 1) / n, _dNear, _dFar),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              r.color.withValues(alpha: r.isPlayer ? 0.20 : 0.10),
              r.color.withValues(alpha: 0.02),
            ],
          ).createShader(Rect.fromLTWH(0, _y(_dFar), _w, _h)),
      );
    }

    // Lane dividers: streaming dashes.
    const span = _dFar - _dNear;
    for (var j = 1; j < n; j++) {
      final t = j / n;
      for (var k = 0; k < 14; k++) {
        final d0 = _dNear + ((k * 0.34 - s.scroll * 1.1) % span + span) % span;
        final d1 = d0 + 0.13;
        final p = Paint()
          ..strokeWidth = 2.6 / d0
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.42 / math.sqrt(d0));
        canvas.drawLine(
            Offset(_edge(t, d0), _y(d0)), Offset(_edge(t, d1), _y(d1)), p);
      }
    }

    // Neon edge rails.
    for (final side in [0.0, 1.0]) {
      final color = side == 0 ? BmColors.cyan : BmColors.pink;
      final a = Offset(_edge(side, _dNear), _y(_dNear));
      final b = Offset(_edge(side, _dFar), _y(_dFar));
      canvas.drawLine(
        a,
        b,
        Paint()
          ..strokeWidth = 10
          ..color = color.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..strokeWidth = 2.4
          ..color = color,
      );
    }

    // Start line.
    canvas.drawLine(
      Offset(_edge(0, _dStart), _y(_dStart)),
      Offset(_edge(1, _dStart), _y(_dStart)),
      Paint()
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  void _finishLine(Canvas canvas) {
    const cols = 14;
    const rows = 2;
    const depth = 0.16;
    final pulse = s.finalStretch ? 0.5 + 0.5 * math.sin(s.time * 8) : 0.0;
    canvas.drawPath(
      _band(0, 1, _dFinish - 0.05, _dFinish + depth + 0.05),
      Paint()
        ..color = BmColors.gold.withValues(alpha: 0.18 + 0.35 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final d0 = _dFinish + depth * r / rows;
        final d1 = _dFinish + depth * (r + 1) / rows;
        canvas.drawPath(
          _band(c / cols, (c + 1) / cols, d0, d1),
          Paint()
            ..color = (r + c).isEven
                ? Colors.white.withValues(alpha: 0.9)
                : const Color(0xFF0B0D22),
        );
      }
    }

    // Finish arch.
    final postH = (_h - _vpY) * 0.16;
    final l = Offset(_edge(-0.02, _dFinish), _y(_dFinish));
    final r = Offset(_edge(1.02, _dFinish), _y(_dFinish));
    final post = Paint()
      ..strokeWidth = 3
      ..color = BmColors.gold;
    canvas.drawLine(l, l.translate(0, -postH), post);
    canvas.drawLine(r, r.translate(0, -postH), post);
    final banner = Rect.fromLTRB(l.dx, l.dy - postH - 16, r.dx, l.dy - postH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(banner, const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(colors: [
          Color(0xFF7B3CFF),
          Color(0xFFB24DFF),
          Color(0xFF7B3CFF),
        ]).createShader(banner),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(banner, const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = BmColors.gold.withValues(alpha: 0.6 + 0.4 * pulse),
    );
    _text(canvas, 'FINISH', banner.center, 11, Colors.white,
        spacing: 4, anchorCenter: true);
  }

  void _laneNumbers(Canvas canvas, int n) {
    for (var i = 0; i < s.racers.length; i++) {
      const d = 0.98;
      final x = _edge((i + 0.5) / n, d);
      _text(canvas, '${i + 1}', Offset(x, _y(d) - 22), 30,
          s.racers[i].color.withValues(alpha: 0.38),
          anchorCenter: true);
    }
  }

  void _car(Canvas canvas, ArenaRacer r, int lane, int n) {
    final shown = s.display[r.id] ?? r.progress.toDouble();
    final d = _depthFor(shown);
    final scale = 1 / d;
    final cx = _edge((lane + 0.5) / n, d);
    final cy = _y(d);
    final laneW = 2 * _half(1) / n;
    final w = math.min(laneW * 0.66, 64.0) * scale;
    final h = w * 0.9;
    final base = r.eliminated ? const Color(0xFF5A6082) : r.color;
    final t = s.time;

    // Shadow and neon under-glow.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: w * 1.25, height: h * 0.3),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    if (!r.eliminated) {
      final fast = r.speed == SpeedStatus.fast;
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, cy), width: w * 1.7, height: h * 0.55),
        Paint()
          ..color = base.withValues(alpha: fast ? 0.55 : 0.32)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * scale),
      );
    }

    // Danger zone pulse.
    if (r.danger && !r.eliminated && !r.finished) {
      final p = 0.5 + 0.5 * math.sin(t * 9);
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, cy - h * 0.1), width: w * 1.9, height: h * 0.8),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * scale + 1
          ..color = BmColors.red.withValues(alpha: 0.35 + 0.55 * p),
      );
    }

    // Exhaust trails stream back towards the camera.
    if (!r.eliminated && !r.finished && r.speed != SpeedStatus.stopped) {
      final boost = r.speed == SpeedStatus.fast ? 2.4 : 1.2;
      final flicker = 0.88 + 0.12 * math.sin(t * 40 + lane);
      final len = h * boost * flicker * (0.6 + s.pace * 0.4);
      for (final side in [-0.26, 0.26]) {
        final top = cy - h * 0.28;
        final rect =
            Rect.fromLTWH(cx + w * side - w * 0.09, top, w * 0.18, len);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(w * 0.09)),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.95),
                base.withValues(alpha: 0.85),
                base.withValues(alpha: 0.0),
              ],
              stops: const [0, 0.25, 1],
            ).createShader(rect),
        );
      }
    }

    // Wheels.
    final wheel = Paint()..color = const Color(0xFF07081A);
    for (final side in [-1, 1]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              cx + side * w * 0.5 - w * 0.1, cy - h * 0.42, w * 0.2, h * 0.42),
          Radius.circular(w * 0.06),
        ),
        wheel,
      );
      canvas.drawLine(
        Offset(cx + side * w * 0.5, cy - h * 0.38),
        Offset(cx + side * w * 0.5, cy - h * 0.06),
        Paint()
          ..strokeWidth = 1.2 * scale + 0.4
          ..color = base.withValues(alpha: 0.9),
      );
    }

    // Body.
    final body = Path()
      ..moveTo(cx - w * 0.44, cy - h * 0.06)
      ..lineTo(cx - w * 0.36, cy - h * 0.58)
      ..quadraticBezierTo(cx, cy - h * 0.70, cx + w * 0.36, cy - h * 0.58)
      ..lineTo(cx + w * 0.44, cy - h * 0.06)
      ..quadraticBezierTo(cx, cy + h * 0.04, cx - w * 0.44, cy - h * 0.06)
      ..close();
    final bodyRect = Rect.fromLTWH(cx - w / 2, cy - h * 0.7, w, h * 0.7);
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(base, Colors.white, 0.45)!,
            base,
            Color.lerp(base, Colors.black, 0.55)!,
          ],
        ).createShader(bodyRect),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.4),
    );

    // Cockpit canopy.
    final canopy = Rect.fromCenter(
        center: Offset(cx, cy - h * 0.66), width: w * 0.46, height: h * 0.32);
    canvas.drawOval(
      canopy,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A3370), Color(0xFF05071A)],
        ).createShader(canopy),
    );
    canvas.drawArc(
      canopy.deflate(w * 0.04),
      math.pi * 1.15,
      math.pi * 0.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.5),
    );

    // Rear wing.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - w * 0.5, cy - h * 0.92, w, h * 0.09),
        Radius.circular(w * 0.03),
      ),
      Paint()..color = Color.lerp(base, Colors.black, 0.25)!,
    );
    for (final side in [-0.22, 0.22]) {
      canvas.drawLine(
        Offset(cx + w * side, cy - h * 0.84),
        Offset(cx + w * side, cy - h * 0.62),
        Paint()
          ..strokeWidth = 1.4 * scale + 0.4
          ..color = Color.lerp(base, Colors.black, 0.4)!,
      );
    }

    // Tail-light bar.
    final tail =
        Rect.fromLTWH(cx - w * 0.33, cy - h * 0.32, w * 0.66, h * 0.07);
    if (!r.eliminated) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(tail.inflate(2), Radius.circular(h * 0.04)),
        Paint()
          ..color = base.withValues(alpha: 0.8)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * scale + 1),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(tail, Radius.circular(h * 0.04)),
      Paint()
        ..color = r.eliminated
            ? const Color(0xFF2A2D44)
            : Color.lerp(base, Colors.white, 0.6)!,
    );

    // Labels above the car.
    final pos = s.positions[r.id] ?? 0;
    final labelY = cy - h * 1.05;
    final badgeR = math.max(7.0, 11 * scale);
    if (r.eliminated) {
      _text(canvas, 'OUT', Offset(cx, labelY - 4), 11, BmColors.red,
          anchorCenter: true, spacing: 2);
    } else if (pos > 0) {
      final c = Offset(cx, labelY - badgeR);
      canvas.drawCircle(
        c,
        badgeR + 2,
        Paint()
          ..color = base.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(c, badgeR, Paint()..color = base);
      _text(canvas, '$pos', c, badgeR * 1.25, BmColors.deep,
          anchorCenter: true);
      if (r.isPlayer) {
        final tip = labelY - badgeR * 2 - 4;
        final m = Path()
          ..moveTo(cx - 6, tip - 8)
          ..lineTo(cx + 6, tip - 8)
          ..lineTo(cx, tip)
          ..close();
        canvas.drawPath(m, Paint()..color = BmColors.gold);
        _text(canvas, 'YOU', Offset(cx, tip - 16), 10, BmColors.gold,
            anchorCenter: true, spacing: 1.5);
      }
    }
    if (r.finished) {
      _text(canvas, 'FINISHED', Offset(cx, cy + 8), 9, BmColors.gold,
          anchorCenter: true, spacing: 1.2);
    }
  }

  void _effects(Canvas canvas, int n) {
    for (final f in s.fx) {
      final lane = s.racers.indexWhere((r) => r.id == f.id);
      if (lane < 0) continue;
      final r = s.racers[lane];
      final d = _depthFor(s.display[r.id] ?? r.progress.toDouble());
      final age = s.time - f.start;
      final a = (1 - age / 1.3).clamp(0.0, 1.0);
      final x = _edge((lane + 0.5) / n, d);
      final h = math.min(2 * _half(1) / n * 0.66, 64.0) / d * 0.9;
      final y = _y(d) - h * 1.6 - 18 - f.lift - age * 34;
      _text(canvas, f.text, Offset(x, y), 15, f.color.withValues(alpha: a),
          anchorCenter: true, shadow: true);
    }
  }

  void _text(Canvas canvas, String text, Offset at, double size, Color color,
      {bool anchorCenter = false, double spacing = 0.5, bool shadow = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: BmText.displayFamily,
          fontSize: size,
          fontWeight: FontWeight.w700,
          letterSpacing: spacing,
          color: color,
          shadows: shadow
              ? [
                  Shadow(
                      color: Colors.black.withValues(alpha: color.a),
                      blurRadius: 6),
                ]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = anchorCenter ? at - Offset(tp.width / 2, tp.height / 2) : at;
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) => old.s != s;
}

/// Seat colour helper shared with the crowd lights.
abstract final class BmSeat {
  static Color colorFor(int i) =>
      BmColors.seatColors[i % BmColors.seatColors.length];
}

/// Live position board: rows slide to their new place on every overtake.
class _Standings extends StatelessWidget {
  const _Standings({
    required this.racers,
    required this.positions,
    required this.distance,
  });

  final List<ArenaRacer> racers;
  final Map<String, int> positions;
  final int distance;

  static const _rowH = 21.0;

  @override
  Widget build(BuildContext context) {
    final ordered = positions.isEmpty
        ? racers
        : ([...racers]..sort((a, b) =>
            (positions[a.id] ?? 99).compareTo(positions[b.id] ?? 99)));
    final slot = {for (var i = 0; i < ordered.length; i++) ordered[i].id: i};
    return Container(
      width: 116,
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFF070B26).withValues(alpha: 0.82),
        border: Border.all(color: BmColors.cyan.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('POSITION', style: BmText.label(7.5, color: BmColors.cyan)),
          const SizedBox(height: 3),
          SizedBox(
            height: _rowH * racers.length,
            child: Stack(
              children: [
                for (final r in racers)
                  AnimatedPositioned(
                    key: ValueKey(r.id),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeInOutCubic,
                    top: (slot[r.id] ?? 0) * _rowH,
                    left: 0,
                    right: 0,
                    height: _rowH - 3,
                    child: _StandingRow(
                      racer: r,
                      place: positions.isEmpty ? 0 : (slot[r.id] ?? 0) + 1,
                      distance: distance,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.racer,
    required this.place,
    required this.distance,
  });

  final ArenaRacer racer;
  final int place;
  final int distance;

  @override
  Widget build(BuildContext context) {
    final c = racer.eliminated ? BmColors.muted : racer.color;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: c.withValues(alpha: racer.isPlayer ? 0.28 : 0.12),
        border: Border.all(
          color: racer.isPlayer ? BmColors.gold : c.withValues(alpha: 0.55),
          width: racer.isPlayer ? 1.2 : 0.8,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            child: Text(
              place == 0 ? '·' : '$place',
              style: BmText.display(10, color: c),
            ),
          ),
          Expanded(
            child: Text(
              racer.eliminated ? '${racer.name} ✕' : racer.name,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: BmText.label(8, color: Colors.white, spacing: 0.4),
            ),
          ),
          SizedBox(
            width: 26,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (racer.progress / distance).clamp(0.0, 1.0),
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(c),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.label, required this.player});

  final String label;
  final ArenaRacer? player;

  @override
  Widget build(BuildContext context) {
    final speed = player?.speed ?? SpeedStatus.stopped;
    final color = switch (speed) {
      SpeedStatus.fast => BmColors.gold,
      SpeedStatus.cruising => BmColors.cyan,
      SpeedStatus.stopped => BmColors.muted,
    };
    final bars = switch (speed) {
      SpeedStatus.fast => 5,
      SpeedStatus.cruising => 3,
      SpeedStatus.stopped => 0,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFF070B26).withValues(alpha: 0.82),
        border: Border.all(color: BmColors.violet.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: BmText.display(13)),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 5; i++)
                Container(
                  width: 6,
                  height: 4.0 + i * 1.6,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    color:
                        i < bars ? color : Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              const SizedBox(width: 4),
              Text(speed.label, style: BmText.label(7.5, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: BmGradients.gold,
        boxShadow: bmGlow(BmColors.gold, blur: 24, opacity: 0.6),
      ),
      child: Text(
        text,
        style: BmText.display(16, color: const Color(0xFF2A1600))
            .copyWith(letterSpacing: 3),
      ),
    );
  }
}

class _FinishFlash extends StatelessWidget {
  const _FinishFlash({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.sports_score_rounded, color: Colors.white, size: 54),
        Text(
          'FINISH!',
          style: BmText.display(46, color: BmColors.gold).copyWith(
            letterSpacing: 6,
            shadows: [
              Shadow(
                color: BmColors.gold.withValues(alpha: 0.8),
                blurRadius: 24,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
