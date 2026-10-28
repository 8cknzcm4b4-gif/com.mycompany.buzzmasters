import 'package:flutter/material.dart';

import '../design/bm_theme.dart';

enum BmButtonStyle { gold, cyan, violet, outline, white }

/// Chunky, neon-lit show button used across every Buzz Masters screen.
class BmButton extends StatelessWidget {
  const BmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = BmButtonStyle.gold,
    this.icon,
    this.height = 56,
    this.fontSize = 15,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final BmButtonStyle style;
  final IconData? icon;
  final double height;
  final double fontSize;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final (gradient, fg, border, glow) = switch (style) {
      BmButtonStyle.gold => (
          BmGradients.gold,
          const Color(0xFF2A1600),
          BmColors.gold,
          BmColors.gold,
        ),
      BmButtonStyle.cyan => (
          BmGradients.cyan,
          const Color(0xFF00212B),
          BmColors.cyan,
          BmColors.cyan,
        ),
      BmButtonStyle.violet => (
          BmGradients.violet,
          Colors.white,
          BmColors.violet,
          BmColors.violet,
        ),
      BmButtonStyle.white => (
          const LinearGradient(colors: [Colors.white, Color(0xFFEDEFF8)]),
          const Color(0xFF11122A),
          Colors.white,
          Colors.white,
        ),
      BmButtonStyle.outline => (
          const LinearGradient(
            colors: [Color(0x22FFFFFF), Color(0x11FFFFFF)],
          ),
          Colors.white,
          BmColors.gold,
          BmColors.gold,
        ),
    };

    final button = Container(
      height: height,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: border.withValues(alpha: 0.9), width: 1.4),
        boxShadow: [
          ...bmGlow(glow,
              blur: 22, opacity: style == BmButtonStyle.outline ? 0.25 : 0.45),
        ],
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: fontSize + 6, color: fg),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: BmText.title(fontSize, color: fg)
                  .copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6),
            ),
          ],
        ),
      ),
    );

    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(height / 2),
          onTap: onPressed,
          child:
              expand ? SizedBox(width: double.infinity, child: button) : button,
        ),
      ),
    );
  }
}

/// Circular neon icon button (back arrows, settings, sound).
class BmIconButton extends StatelessWidget {
  const BmIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color = BmColors.cyan,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(size),
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BmColors.panel.withValues(alpha: 0.75),
            border: Border.all(color: color.withValues(alpha: 0.7), width: 1.2),
            boxShadow: bmGlow(color, blur: 14, opacity: 0.35),
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
  }
}
