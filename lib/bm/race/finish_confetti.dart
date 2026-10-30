import 'dart:math';

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';

/// A one-shot confetti burst shown when a race finishes.
///
/// Pieces are plain widgets rather than a canvas painter, so the burst is
/// clipped to its bounds and never blocks taps on the results underneath.
class FinishConfetti extends StatefulWidget {
  const FinishConfetti({super.key, this.pieceCount = 26});

  /// Number of strips in the burst.
  final int pieceCount;

  @override
  State<FinishConfetti> createState() => _FinishConfettiState();
}

class _FinishConfettiState extends State<FinishConfetti>
    with SingleTickerProviderStateMixin {
  static const _colors = [
    BmColors.gold,
    BmColors.cyan,
    BmColors.green,
    Color(0xFFFF5CA8),
    Color(0xFFFFA53D),
    Color(0xFF9C6CFF),
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();

  late final List<_Piece> _pieces = _buildPieces();

  List<_Piece> _buildPieces() {
    final rng = Random(7);
    return [
      for (var i = 0; i < widget.pieceCount; i++)
        _Piece(
          angle: rng.nextDouble() * 2 * pi,
          distance: 0.35 + rng.nextDouble() * 0.65,
          spin: (rng.nextDouble() - 0.5) * 6,
          color: _colors[i % _colors.length],
          width: 4 + rng.nextDouble() * 4,
        ),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final travel = Curves.easeOutCubic.transform(t);
            final opacity = (1 - t).clamp(0.0, 1.0);
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                if (!width.isFinite || !height.isFinite) {
                  return const SizedBox.shrink();
                }
                const originY = 0.42;
                return Stack(
                  children: [
                    for (final piece in _pieces)
                      Positioned(
                        left: width / 2 +
                            cos(piece.angle) *
                                piece.distance *
                                width *
                                0.55 *
                                travel,
                        top: height * originY +
                            sin(piece.angle) *
                                piece.distance *
                                height *
                                0.32 *
                                travel +
                            height * 0.35 * t * t,
                        child: Opacity(
                          opacity: opacity,
                          child: Transform.rotate(
                            angle: piece.spin * t,
                            child: Container(
                              width: piece.width,
                              height: piece.width * 1.8,
                              decoration: BoxDecoration(
                                color: piece.color,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.angle,
    required this.distance,
    required this.spin,
    required this.color,
    required this.width,
  });

  final double angle;
  final double distance;
  final double spin;
  final Color color;
  final double width;
}
