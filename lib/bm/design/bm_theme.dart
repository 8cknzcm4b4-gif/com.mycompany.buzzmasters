import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Neon Turbo Quiz Arena palette.
///
/// Deep midnight navy surfaces, ultraviolet and electric purple light, neon
/// cyan highlights and gold reserved for wins, rewards and VIP.
class BmColors {
  BmColors._();

  static const deep = Color(0xFF03051A);
  static const midnight = Color(0xFF080D2C);
  static const stage = Color(0xFF130A3D);
  static const violet = Color(0xFF7B3CFF);
  static const purple = Color(0xFFB24DFF);
  static const cyan = Color(0xFF22E6FF);
  static const gold = Color(0xFFFFC94A);
  static const pink = Color(0xFFFF3DAE);
  static const green = Color(0xFF2EF2A0);
  static const panel = Color(0xFF10163D);
  static const panelEdge = Color(0xFF2A3170);
  static const muted = Color(0xFF8E97C8);
  static const red = Color(0xFFFF4566);

  /// Six lane colours, one per racer seat.
  static const seatColors = <Color>[
    Color(0xFFFF3DAE),
    Color(0xFF22E6FF),
    Color(0xFFA65BFF),
    Color(0xFFFFC94A),
    Color(0xFF2EF2A0),
    Color(0xFF4D8DFF),
  ];
}

class BmGradients {
  BmGradients._();

  static const gold = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF0B3), Color(0xFFFFC94A), Color(0xFFE08A1E)],
  );

  static const silver = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFCFE0FF), Color(0xFF8299D6)],
  );

  static const bronze = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFD2A8), Color(0xFFE08A4F), Color(0xFF9A4F26)],
  );

  static const violet = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB24DFF), Color(0xFF6A2BFF)],
  );

  static const cyan = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7AF4FF), Color(0xFF18B8FF)],
  );

  static const panel = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xEB161E52), Color(0xEB0A0F30)],
  );
}

class BmText {
  BmText._();

  /// Bundled display face (SIL OFL), so headings never wait on the network.
  static const displayFamily = 'Rajdhani';

  /// Rajdhani is narrower than Poppins, so display sizes are scaled to keep
  /// existing call sites visually balanced.
  static const _displayScale = 1.14;

  static TextStyle display(double size, {Color color = Colors.white}) =>
      TextStyle(
        fontFamily: displayFamily,
        fontSize: size * _displayScale,
        fontWeight: FontWeight.w700,
        height: 1.0,
        letterSpacing: 0.6,
        color: color,
      );

  static TextStyle title(double size, {Color color = Colors.white}) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: color,
      );

  static TextStyle body(double size,
          {Color color = Colors.white, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: weight,
        height: 1.35,
        color: color,
      );

  static TextStyle label(double size,
          {Color color = BmColors.muted, double spacing = 1.6}) =>
      TextStyle(
        fontFamily: displayFamily,
        fontSize: size * 1.18,
        fontWeight: FontWeight.w700,
        letterSpacing: spacing,
        height: 1.1,
        color: color,
      );
}

/// Shared neon glow used by buttons, podiums and panels.
List<BoxShadow> bmGlow(Color color,
        {double blur = 28, double opacity = 0.55}) =>
    [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blur,
        spreadRadius: 0.5,
      ),
    ];
