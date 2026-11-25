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
  cursive('Cursiva y journaling'),
  calligraphy('Caligrafía elegante'),
  handwritten('Letra a mano (cuaderno)'),
  lettering('Lettering y títulos'),
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

  // Cursivas y a mano para journaling (Google Fonts, licencia libre).
  AppFont('Dancing Script', 'Dancing Script · cursiva clásica',
      group: FontGroup.cursive, sample: 'Querido diario, hoy…'),
  AppFont('Great Vibes', 'Great Vibes · caligrafía elegante',
      group: FontGroup.cursive, sample: 'Querido diario, hoy…'),
  AppFont('Allura', 'Allura · cursiva fina', group: FontGroup.cursive, sample: 'Querido diario, hoy…'),
  AppFont('Parisienne', 'Parisienne · romántica',
      group: FontGroup.cursive, sample: 'Querido diario, hoy…'),
  AppFont('Sacramento', 'Sacramento · monolínea',
      group: FontGroup.cursive, sample: 'Querido diario, hoy…'),
  AppFont('Satisfy', 'Satisfy · cursiva suelta', group: FontGroup.cursive, sample: 'Querido diario, hoy…'),
  AppFont('Pacifico', 'Pacifico · títulos divertidos',
      group: FontGroup.cursive, sample: 'Querido diario, hoy…'),
  AppFont('Homemade Apple', 'Homemade Apple · letra real',
      group: FontGroup.cursive, sample: 'Querido diario, hoy…'),
  AppFont('Indie Flower', 'Indie Flower · a mano redondita',
      group: FontGroup.cursive, sample: 'Querido diario, hoy…'),
  AppFont('Shadows Into Light', 'Shadows Into Light · plumón',
      group: FontGroup.cursive, sample: 'Querido diario, hoy…'),
  AppFont('Gloria Hallelujah', 'Gloria Hallelujah · cuaderno',
      group: FontGroup.cursive, sample: 'Querido diario, hoy…'),
  AppFont('Amatic SC', 'Amatic SC · títulos finos',
      group: FontGroup.cursive, sample: 'QUERIDO DIARIO'),

  // Chino manuscrito (Google Fonts, licencia libre OFL).
  // calligraphy
  AppFont('Alex Brush', 'Alex Brush · pincel fino', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Pinyon Script', 'Pinyon Script · caligrafía clásica', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Tangerine', 'Tangerine · pluma', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Italianno', 'Italianno · itálica', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Petit Formal Script', 'Petit Formal · formal', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Mrs Saint Delafield', 'Mrs Saint Delafield · firma', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Herr Von Muellerhoff', 'Herr Von Muellerhoff · firma', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Monsieur La Doulaise', 'Monsieur La Doulaise · antigua', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Rouge Script', 'Rouge Script · romántica', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Ephesis', 'Ephesis · delicada', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Ms Madi', 'Ms Madi · moderna', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Love Light', 'Love Light · suave', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Hurricane', 'Hurricane · pincel suelto', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Meow Script', 'Meow Script · juguetona', group: FontGroup.calligraphy, sample: 'Querido diario'),
  AppFont('Ballet', 'Ballet · bailarina', group: FontGroup.calligraphy, sample: 'Querido diario'),

  // handwritten
  AppFont('Kalam', 'Kalam · a mano clara', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Caveat Brush', 'Caveat Brush · plumón', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Nanum Pen Script', 'Nanum Pen · bolígrafo', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Reenie Beanie', 'Reenie Beanie · rápida', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Nothing You Could Do', 'Nothing You Could Do · diario', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('La Belle Aurore', 'La Belle Aurore · inclinada', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Covered By Your Grace', 'Covered By Your Grace · marcador', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Just Another Hand', 'Just Another Hand · alta', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Annie Use Your Telescope', 'Annie · redondita', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Architects Daughter', 'Architects Daughter · ordenada', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Handlee', 'Handlee · escolar', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Gaegu', 'Gaegu · tierna', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Mali', 'Mali · cute', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Zeyada', 'Zeyada · apurada', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),
  AppFont('Bad Script', 'Bad Script · cursiva real', group: FontGroup.handwritten, sample: 'Hoy aprendí algo nuevo'),

  // lettering
  AppFont('Kaushan Script', 'Kaushan Script · brush lettering', group: FontGroup.lettering, sample: 'Mis metas ✨'),
  AppFont('Cookie', 'Cookie · retro', group: FontGroup.lettering, sample: 'Mis metas ✨'),
  AppFont('Yellowtail', 'Yellowtail · vintage', group: FontGroup.lettering, sample: 'Mis metas ✨'),
  AppFont('Lobster', 'Lobster · títulos', group: FontGroup.lettering, sample: 'Mis metas ✨'),
  AppFont('Marck Script', 'Marck Script · marcador', group: FontGroup.lettering, sample: 'Mis metas ✨'),
  AppFont('Sniglet', 'Sniglet · burbuja', group: FontGroup.lettering, sample: 'Mis metas ✨'),
  AppFont('Fredoka', 'Fredoka · redonda', group: FontGroup.lettering, sample: 'Mis metas ✨'),
  AppFont('Chewy', 'Chewy · divertida', group: FontGroup.lettering, sample: 'Mis metas ✨'),
  AppFont('Bungee Shade', 'Bungee Shade · sombra', group: FontGroup.lettering, sample: 'Mis metas ✨'),
  AppFont('Rubik Doodle Shadow', 'Rubik Doodle · garabato', group: FontGroup.lettering, sample: 'Mis metas ✨'),

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
