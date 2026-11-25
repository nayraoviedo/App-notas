import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Fuentes disponibles para los bloques de texto.
///
/// Se descargan de Google Fonts la primera vez y quedan en caché. Para que
/// funcionen 100 % sin internet desde el inicio, copia los .ttf a
/// `assets/google_fonts/` y decláralos en pubspec.yaml (ver README).
class AppFont {
  const AppFont(this.family, this.label);

  /// null = fuente del sistema.
  final String? family;
  final String label;
}

const appFonts = <AppFont>[
  AppFont(null, 'Sistema'),
  AppFont('Inter', 'Moderna'),
  AppFont('Merriweather', 'Clásica (serif)'),
  AppFont('Lora', 'Elegante'),
  AppFont('Caveat', 'Manuscrita'),
  AppFont('Patrick Hand', 'A mano (clara)'),
  AppFont('Comic Neue', 'Informal'),
  AppFont('Source Code Pro', 'Código'),
  AppFont('Playfair Display', 'Títulos'),
];

/// Tamaños sugeridos.
const fontSizes = <double>[14, 16, 18, 20, 24, 30];

TextStyle fontStyle(String? family, {double? size, TextStyle? base}) {
  final b = (base ?? const TextStyle()).copyWith(fontSize: size);
  if (family == null) return b;
  try {
    return GoogleFonts.getFont(family, textStyle: b);
  } catch (_) {
    return b; // fuente desconocida: usar la del sistema
  }
}
