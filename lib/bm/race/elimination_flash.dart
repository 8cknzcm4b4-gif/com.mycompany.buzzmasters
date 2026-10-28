import 'dart:math';

import 'package:flutter/material.dart';

/// The elimination beat for one lane: a red flash and a damped stumble.
///
/// Wrap a lane in this only while its racer is being eliminated. The widget
/// runs once on mount, then leaves the lane in its OUT state.
class EliminationFlash extends StatefulWidget {
  const EliminationFlash({super.key, required this.child});

  final Widget child;

  @override
  State<EliminationFlash> createState() => _EliminationFlashState();
}

class _EliminationFlashState extends State<EliminationFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Red glow flashes at full strength, then fades as the racer settles.
        final flash = (1 - t) * 0.5;
        // Two quick side-to-side stumbles that damp out.
        final stumble = sin(t * 18) * 6 * (1 - t);
        return Transform.translate(
          offset: Offset(stumble, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withValues(alpha: flash),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
