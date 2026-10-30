import 'package:flutter/material.dart';

import '../design/bm_theme.dart';

/// The pre-race start gantry: a row of lights that turn red one per second,
/// a huge 3, 2, 1, then every light flips green for GO.
class RaceCountdown extends StatelessWidget {
  const RaceCountdown({super.key, required this.secondsLeft, this.total = 3});

  /// Seconds remaining; zero means the race is starting.
  final int secondsLeft;
  final int total;

  @override
  Widget build(BuildContext context) {
    final started = secondsLeft <= 0;
    final label = started ? 'GO!' : '$secondsLeft';
    final color = started ? BmColors.green : BmColors.gold;
    final lit = started ? total : (total - secondsLeft + 1).clamp(0, total);
    return SizedBox(
      height: 190,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: const Color(0xFF05071A).withValues(alpha: 0.9),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < total; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < lit
                          ? (started ? BmColors.green : BmColors.red)
                          : const Color(0xFF1C2040),
                      boxShadow: i < lit
                          ? bmGlow(started ? BmColors.green : BmColors.red,
                              blur: 16, opacity: 0.9)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 1.8, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              label,
              key: ValueKey<String>(label),
              style: BmText.display(76, color: color).copyWith(
                shadows: [
                  Shadow(color: color.withValues(alpha: 0.9), blurRadius: 28),
                ],
              ),
            ),
          ),
          Text(
            started ? 'RACE!' : 'GET READY',
            style:
                BmText.label(12, color: started ? BmColors.green : Colors.white)
                    .copyWith(letterSpacing: 4),
          ),
        ],
      ),
    );
  }
}
