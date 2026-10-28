import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Core colour palette for Buzz Masters.
class BmColors {
  BmColors._();

  static const midnight = Color(0xFF11122A);
  static const deep = Color(0xFF07060F);
  static const stage = Color(0xFF1A1040);
  static const violet = Color(0xFF7545EF);
  static const cyan = Color(0xFF00D8F4);
  static const gold = Color(0xFFFFCB45);
  static const pink = Color(0xFFFF4E87);
  static const green = Color(0xFF35D07F);
  static const panel = Color(0xFF1B1C3A);
  static const panelEdge = Color(0xFF2E2F5C);
  static const muted = Color(0xFF9AA0C4);
  static const red = Color(0xFFFF3B3B);

  /// Per-seat neon accents, mirroring the six podium colours in the design.
  static const seatColors = <Color>[
    Color(0xFF3D8BFF),
    Color(0xFFFF4E87),
    Color(0xFF35D07F),
    Color(0xFFFFCB45),
    Color(0xFF9B6BFF),
    Color(0xFF00D8F4),
  ];
}

class BmGradients {
  BmGradients._();

  static const gold = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFE89A), Color(0xFFFFCB45), Color(0xFFE8942B)],
  );

  static const silver = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFCDE6FF), Color(0xFF7FA8E8)],
  );

  static const violet = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9B6BFF), Color(0xFF7545EF)],
  );

  static const cyan = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5BEBFF), Color(0xFF00D8F4)],
  );

  static const panel = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF23244A), Color(0xFF161737)],
  );
}

class BmText {
  BmText._();

  static TextStyle display(double size, {Color color = Colors.white}) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w900,
        height: 1.02,
        letterSpacing: -0.5,
        color: color,
      );

  static TextStyle title(double size, {Color color = Colors.white}) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.15,
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
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: spacing,
        color: color,
      );
}

/// Shared neon glow used by buttons, podiums and panels.
List<BoxShadow> bmGlow(Color color,
        {double blur = 28, double opacity = 0.55}) =>
    [
      BoxShadow(
        color: color.withOpacity(opacity),
        blurRadius: blur,
        spreadRadius: 1,
      ),
    ];
