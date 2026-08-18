import 'package:flutter/material.dart';

/// JeonChat design tokens — dark theme styled after ChatGPT Plus.
class JeonColors {
  static const bg = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const surface2 = Color(0xFF1C2128);
  static const surface3 = Color(0xFF21262D);
  static const border = Color(0xFF30363D);
  static const borderSoft = Color(0xFF21262D);

  static const ink = Color(0xFFE6EDF3);
  static const inkMuted = Color(0xFF8B949E);
  static const inkFaint = Color(0xFF6E7681);

  static const accent = Color(0xFF58A6FF);
  static const accentDim = Color(0xFF388BFD);
  static const accentGlow = Color(0x2958A6FF); // rgba(88,166,255,0.16)

  static const danger = Color(0xFFF85149);
  static const warn = Color(0xFFD29922);
}

class JeonRadius {
  static const card = 10.0;
  static const small = 7.0;
  static const bubble = 16.0;
  static const pill = 24.0;
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
