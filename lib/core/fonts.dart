import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Fuentes disponibles para los bloques de texto.
///
/// Se descargan de Google Fonts la primera vez y quedan en caché. Las chinas
/// pesan varios MB cada una, así que la primera vez tardan un poco más.
/// Para que funcionen 100 % sin internet desde el inicio, copia los .ttf a
/// `assets/google_fonts/` y decláralos en pubspec.yaml (ver README).
class AppFont {
  const AppFont(this.family, this.label, {this.group = FontGroup.latin, this.sample});

  /// null = fuente del sistema.
  final String? family;
  final String label;
  final FontGroup group;

  /// Texto de ejemplo para el selector (si no, se usa el nombre).
  final String? sample;
}

enum FontGroup {
  latin('Generales'),
  chinese('Chino manuscrito y caligrafía'),
  chineseText('Chino para texto');

  const FontGroup(this.label);
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

  // Chino manuscrito (Google Fonts, licencia libre OFL).
  AppFont('Long Cang', 'Long Cang · a mano', group: FontGroup.chinese, sample: '今天的笔记：你好，世界'),
  AppFont('Zhi Mang Xing', 'Zhi Mang Xing · escritura corrida',
      group: FontGroup.chinese, sample: '今天的笔记：你好，世界'),
  AppFont('Liu Jian Mao Cao', 'Liu Jian Mao Cao · escritura de hierba',
      group: FontGroup.chinese, sample: '今天的笔记：你好，世界'),
  AppFont('Ma Shan Zheng', 'Ma Shan Zheng · caligrafía con pincel',
      group: FontGroup.chinese, sample: '今天的笔记：你好，世界'),
  AppFont('ZCOOL KuaiLe', 'ZCOOL KuaiLe · divertida',
      group: FontGroup.chinese, sample: '今天的笔记：你好，世界'),
  AppFont('ZCOOL XiaoWei', 'ZCOOL XiaoWei · serif elegante',
      group: FontGroup.chinese, sample: '今天的笔记：你好，世界'),

  // Chino legible para textos largos.
  AppFont('Noto Sans SC', 'Noto Sans · simplificado',
      group: FontGroup.chineseText, sample: '今天的笔记：你好，世界'),
  AppFont('Noto Serif SC', 'Noto Serif · simplificado',
      group: FontGroup.chineseText, sample: '今天的笔记：你好，世界'),
  AppFont('Noto Sans TC', 'Noto Sans · tradicional',
      group: FontGroup.chineseText, sample: '今天的筆記：你好，世界'),
];

/// Tamaños sugeridos.
const fontSizes = <double>[14, 16, 18, 20, 24, 30, 36];

TextStyle fontStyle(String? family, {double? size, TextStyle? base}) {
  final b = (base ?? const TextStyle()).copyWith(fontSize: size);
  if (family == null) return b;
  try {
    return GoogleFonts.getFont(family, textStyle: b);
  } catch (_) {
    return b; // fuente desconocida: usar la del sistema
  }
}

/// ¿El texto tiene caracteres chinos/japoneses (CJK)?
bool hasCjk(String text) => RegExp(r'[㐀-鿿豈-﫿]').hasMatch(text);
