import 'package:flutter/material.dart';

import '../design/bm_theme.dart';

/// One finisher on the podium.
class PodiumEntry {
  const PodiumEntry({
    required this.name,
    required this.color,
    required this.detail,
    this.isPlayer = false,
  });

  final String name;
  final Color color;
  final String detail;
  final bool isPlayer;
}

/// Podium ceremony: second, first and third rise in turn, each racer lands on
/// their step, and the winner gets the gold crown and spotlight.
class RacePodium extends StatefulWidget {
  const RacePodium({super.key, required this.entries, this.height = 230});

  /// Finishers in placing order; only the first three are shown.
  final List<PodiumEntry> entries;
  final double height;

  @override
  State<RacePodium> createState() => _RacePodiumState();
}

class _RacePodiumState extends State<RacePodium>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Visual order: 2nd, 1st, 3rd.
    const slots = [1, 0, 2];
    const stepHeights = [0.75, 1.0, 0.55];
    const gradients = [
      BmGradients.silver,
      BmGradients.gold,
      BmGradients.bronze
    ];
    const delays = [0.25, 0.5, 0.0];
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          children: [
            // Winner spotlight.
            Positioned.fill(
              child: Opacity(
                opacity: Curves.easeIn
                    .transform(((_c.value - 0.55) / 0.45).clamp(0.0, 1.0)),
                child: CustomPaint(painter: _SpotlightPainter()),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var v = 0; v < 3; v++)
                  Expanded(
                    child: slots[v] < widget.entries.length
                        ? _step(
                            entry: widget.entries[slots[v]],
                            place: slots[v] + 1,
                            stepFraction: stepHeights[v],
                            gradient: gradients[v],
                            t: Curves.easeOutBack.transform(
                                ((_c.value - delays[v]) / 0.5).clamp(0.0, 1.0)),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _step({
    required PodiumEntry entry,
    required int place,
    required double stepFraction,
    required LinearGradient gradient,
    required double t,
  }) {
    // The racer's name block takes ~130px; the steps share what is left.
    final maxStep = (widget.height - 132).clamp(40.0, 400.0);
    final stepH = maxStep * stepFraction * t.clamp(0.0, 1.0);
    final avatar = place == 1 ? 62.0 : 50.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Column(
              children: [
                if (place == 1)
                  const Icon(Icons.workspace_premium_rounded,
                      color: BmColors.gold, size: 26),
                Container(
                  width: avatar,
                  height: avatar,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      Color.lerp(entry.color, Colors.white, 0.35)!,
                      entry.color,
                    ]),
                    border: Border.all(
                      color: entry.isPlayer ? BmColors.gold : Colors.white,
                      width: entry.isPlayer ? 3 : 2,
                    ),
                    boxShadow: bmGlow(entry.color, blur: 20, opacity: 0.7),
                  ),
                  child: Text(
                    entry.name.isEmpty ? '?' : entry.name[0].toUpperCase(),
                    style: BmText.display(avatar * 0.42, color: BmColors.deep),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.isPlayer ? '${entry.name} (YOU)' : entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BmText.title(12),
                ),
                Text(entry.detail,
                    style: BmText.label(8.5, color: BmColors.muted)),
                const SizedBox(height: 4),
              ],
            ),
          ),
          Container(
            height: stepH,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              boxShadow: bmGlow(gradient.colors[1], blur: 18, opacity: 0.45),
            ),
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 4),
            child: stepH > 30
                ? Text(
                    '$place',
                    style: BmText.display(30,
                        color: Colors.black.withValues(alpha: 0.55)),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.47, 0)
      ..lineTo(size.width * 0.53, 0)
      ..lineTo(size.width * 0.68, size.height)
      ..lineTo(size.width * 0.32, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BmColors.gold.withValues(alpha: 0.0),
            BmColors.gold.withValues(alpha: 0.22),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
