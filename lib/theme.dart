import 'package:flutter/material.dart';

/// JeonChat design tokens — mirrors /opt/data/jeonchat_ui_mockup.html exactly.
class JeonColors {
  static const bg = Color(0xFF0A0B0A);
  static const surface = Color(0xFF101210);
  static const surface2 = Color(0xFF161916);
  static const surface3 = Color(0xFF1D211D);
  static const border = Color(0xFF262B26);
  static const borderSoft = Color(0xFF1A1E1A);

  static const ink = Color(0xFFEEF3EE);
  static const inkMuted = Color(0xFF9AA79A);
  static const inkFaint = Color(0xFF5F6B5F);

  static const accent = Color(0xFF22C55E);
  static const accentDim = Color(0xFF1A9C49);
  static const accentGlow = Color(0x2422C55E); // rgba(34,197,94,0.14)

  static const danger = Color(0xFFEF4444);
  static const warn = Color(0xFFF59E0B);
}

class JeonRadius {
  static const card = 10.0;
  static const small = 7.0;
}

ThemeData buildJeonTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: JeonColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: JeonColors.accent,
      brightness: Brightness.dark,
      surface: JeonColors.surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: JeonColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: JeonColors.ink,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: JeonColors.surface,
    ),
    textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: JeonColors.ink,
          displayColor: JeonColors.ink,
        ),
    fontFamily: 'Roboto',
  );
}
