import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Letras para toda la app (manuscritas, que se lean bien en botones y listas).
const uiFonts = <String, String>{
  'Patrick Hand': 'Manuscrita clara (recomendada)',
  'Mali': 'Redondita',
  'Itim': 'Cuaderno',
  'Gaegu': 'Tierna',
  'Normal': 'Normal (Roboto)',
};

class AppTheme {
  // Colores cálidos del inicio: crema, terracota y tinta café oscuro.
  static const _seed = Color(0xFFE07B55);
  static const cream = Color(0xFFFFF9EE);
  static const ink = Color(0xFF3B2A22);

  static TextTheme _text(TextTheme base, String font, Color color) {
    // El tema base no trae tamaños: se toman los de Material 3 para poder
    // agrandar la letra manuscrita.
    base = base.merge(Typography.englishLike2021);
    final t = font == 'Normal' ? base : _safe(font, base);
    // Las manuscritas se ven más chicas: un poco más grandes.
    final scaled = font == 'Normal' ? t : t.apply(fontSizeFactor: 1.1);
    return scaled.apply(bodyColor: color, displayColor: color);
  }

  static TextTheme _safe(String font, TextTheme base) {
    try {
      return GoogleFonts.getTextTheme(font, base);
    } catch (_) {
      return base;
    }
  }

  static ThemeData light([String font = 'Patrick Hand']) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, surface: cream).copyWith(
      onSurface: ink,
      onSurfaceVariant: const Color(0xFF5C4A40),
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: cream,
      textTheme: _text(base.textTheme, font, ink),
      appBarTheme: const AppBarTheme(backgroundColor: cream, foregroundColor: ink),
    );
  }

  static ThemeData dark([String font = 'Patrick Hand']) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(textTheme: _text(base.textTheme, font, scheme.onSurface));
  }
}
