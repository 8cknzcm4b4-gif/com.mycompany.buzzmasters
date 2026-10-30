import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/bm_theme.dart';
import '../settings/bm_audio_settings.dart';

enum BmButtonStyle { gold, cyan, violet, outline, white }

/// Neon game button with a glossy sheen, a press-down scale and an optional
/// haptic tick, used across every Buzz Masters screen.
class BmButton extends StatefulWidget {
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
  State<BmButton> createState() => _BmButtonState();
}

class _BmButtonState extends State<BmButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _tap() {
    if (BmAudioSettings.hapticsEnabled) {
      HapticFeedback.selectionClick().catchError((Object _) {});
    }
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final (gradient, fg, border, glow) = switch (widget.style) {
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
          BmColors.purple,
          BmColors.violet,
        ),
      BmButtonStyle.white => (
          const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFE3E7F8)],
          ),
          const Color(0xFF0B0F2C),
          Colors.white,
          Colors.white,
        ),
      BmButtonStyle.outline => (
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1C2466).withValues(alpha: 0.85),
              const Color(0xFF0C1137).withValues(alpha: 0.85),
            ],
          ),
          Colors.white,
          BmColors.cyan,
          BmColors.cyan,
        ),
    };
    final enabled = widget.onPressed != null;
    final radius = BorderRadius.circular(widget.height * 0.32);
    final outline = widget.style == BmButtonStyle.outline;

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: widget.height,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(
          color: border.withValues(alpha: outline ? 0.55 : 0.95),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: Offset(0, _pressed ? 2 : 6),
          ),
          ...bmGlow(
            glow,
            blur: _pressed ? 14 : 24,
            opacity: outline ? 0.18 : (_pressed ? 0.6 : 0.42),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: outline ? 0.06 : 0.28),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: widget.fontSize + 6, color: fg),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BmText.display(widget.fontSize + 1, color: fg)
                    .copyWith(letterSpacing: 1.2),
              ),
            ),
          ],
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: Semantics(
        button: true,
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: enabled ? _tap : null,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1,
            duration: const Duration(milliseconds: 100),
            child: widget.expand
                ? SizedBox(width: double.infinity, child: button)
                : button,
          ),
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
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: BmGradients.panel,
            border: Border.all(color: color.withValues(alpha: 0.7), width: 1.2),
            boxShadow: bmGlow(color, blur: 14, opacity: 0.3),
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// Standard screen header: back control, centred title with optional
/// subtitle, and an optional trailing action.
class ArenaHeader extends StatelessWidget {
  const ArenaHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onBack,
    this.showBack = true,
    this.titleColor = Colors.white,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onBack;
  final bool showBack;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: showBack
                ? Center(
                    child: BmIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed:
                          onBack ?? () => Navigator.of(context).maybePop(),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BmText.display(20, color: titleColor)
                      .copyWith(letterSpacing: 2),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BmText.label(9, color: BmColors.cyan),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 48, child: Center(child: trailing)),
        ],
      ),
    );
  }
}
