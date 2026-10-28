import 'package:flutter/material.dart';

import '../design/bm_theme.dart';

/// The pre-race countdown: 3, 2, 1, then GO.
///
/// Each value pops in with a scale and fade so every second reads as a beat,
/// and the final GO turns green with a brighter glow.
class RaceCountdown extends StatelessWidget {
  const RaceCountdown({super.key, required this.secondsLeft});

  /// Seconds remaining; zero means the race is starting.
  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    final started = secondsLeft <= 0;
    final label = started ? 'GO!' : '$secondsLeft';
    final color = started ? BmColors.green : BmColors.gold;
    return SizedBox(
      height: 150,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.55, end: 1.0).animate(animation),
                child: child,
              ),
            );
          },
          child: Column(
            key: ValueKey<String>(label),
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 26,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(label, style: BmText.display(64, color: color)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                started ? 'RACE!' : 'GET READY',
                style: BmText.label(
                  10,
                  color: started ? BmColors.green : BmColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
