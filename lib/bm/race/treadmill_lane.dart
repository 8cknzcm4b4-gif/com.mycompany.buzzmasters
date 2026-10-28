import 'package:flutter/material.dart';

import '../design/bm_theme.dart';
import 'race_model.dart';

/// One racer's treadmill lane: a scrolling belt, a runner placed by progress,
/// and a finish flag at the far end. Shared by practice racing and time trials.
class TreadmillLane extends StatelessWidget {
  const TreadmillLane({
    super.key,
    required this.name,
    required this.position,
    required this.speed,
    required this.progress,
    required this.distance,
    required this.beltOffset,
    required this.laneColor,
    required this.finished,
    required this.eliminated,
    required this.warning,
    required this.nearFinish,
    this.opacity = 1,
  });

  final String name;
  final int position;
  final SpeedStatus speed;
  final int progress;
  final int distance;
  final double beltOffset;
  final Color laneColor;
  final bool finished;
  final bool eliminated;
  final bool warning;
  final bool nearFinish;

  /// Dims the lane, used for the ghost of a previous run.
  final double opacity;

  static const _laneHeight = 40.0;
  static const _runnerSize = 30.0;
  static const _flagWidth = 22.0;

  @override
  Widget build(BuildContext context) {
    final color = eliminated
        ? BmColors.muted
        : warning
            ? Colors.redAccent
            : laneColor;
    final lane = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              eliminated || position == 0 ? '-' : '$position',
              style: BmText.label(10, color: BmColors.gold),
            ),
          ),
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eliminated ? '$name OUT' : name,
                  style: BmText.body(11, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  finished ? 'FINISHED' : speed.label,
                  style: BmText.label(
                    8,
                    color: finished ? BmColors.gold : BmColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final travel =
                    constraints.maxWidth - _runnerSize - _flagWidth;
                final fraction = (progress / distance).clamp(0.0, 1.0);
                return SizedBox(
                  height: _laneHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _BeltPainter(
                            offset: beltOffset,
                            color: color,
                          ),
                        ),
                      ),
                      if (nearFinish && !finished && !eliminated)
                        Positioned(
                          right: _flagWidth - 6,
                          top: 4,
                          bottom: 4,
                          width: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: BmColors.gold.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: _flagWidth,
                        child: Icon(
                          finished
                              ? Icons.emoji_events_rounded
                              : Icons.flag_rounded,
                          color: BmColors.gold,
                          size: nearFinish ? 24 : 20,
                        ),
                      ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOut,
                        left: travel * fraction,
                        top: (_laneHeight - _runnerSize) / 2,
                        width: _runnerSize,
                        height: _runnerSize,
                        child: _Runner(initial: name[0], color: color),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$progress',
              textAlign: TextAlign.right,
              style: BmText.body(12),
            ),
          ),
        ],
      ),
    );
    return opacity >= 1 ? lane : Opacity(opacity: opacity, child: lane);
  }
}

class _Runner extends StatelessWidget {
  const _Runner({required this.initial, required this.color});

  final String initial;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: BmColors.panel,
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
        ],
      ),
      child: Center(
        child: Text(initial, style: BmText.title(13, color: color)),
      ),
    );
  }
}

/// Paints a dark belt with diagonal rungs that scroll with [offset].
class _BeltPainter extends CustomPainter {
  _BeltPainter({required this.offset, required this.color});

  final double offset;
  final Color color;

  static const _period = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final belt = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(belt, Paint()..color = Colors.black54);
    canvas.save();
    canvas.clipRRect(belt);
    final rung = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 2;
    final shift = offset % _period;
    for (var x = -_period + shift; x < size.width + _period; x += _period) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height * 0.5, 0),
        rung,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      belt,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_BeltPainter old) =>
      old.offset != offset || old.color != color;
}
