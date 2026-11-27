import 'dart:math' as math;
import 'dart:ui';

/// Hojas para practicar caligrafía china (字帖): cada fila tiene un carácter
/// modelo, varias copias tenues para calcar y celdas vacías para escribir solo.

/// Tipo de cuadrícula de cada celda.
enum PracticeGrid {
  tianzi('田字格', 'Cruz al centro'),
  mizi('米字格', 'Cruz y diagonales'),
  jiugong('九宫格', 'Nueve casillas'),
  plain('方格', 'Solo el cuadro');

  const PracticeGrid(this.hanzi, this.label);
  final String hanzi;
  final String label;
}

class PracticeChar {
  const PracticeChar(this.char, [this.pinyin, this.meaning]);
  final String char;
  final String? pinyin;
  final String? meaning;

  Map<String, Object?> toJson() =>
      {'c': char, if (pinyin != null) 'p': pinyin, if (meaning != null) 'm': meaning};

  factory PracticeChar.fromJson(Map<String, Object?> j) =>
      PracticeChar(j['c']! as String, j['p'] as String?, j['m'] as String?);
}

/// Configuración guardada dentro de la hoja.
class PracticeSheet {
  const PracticeSheet({
    required this.chars,
    this.grid = PracticeGrid.tianzi,
    this.font = 'Ma Shan Zheng',
    this.traceCount = 3,
    this.cellSize = 84,
    this.showPinyin = true,
  });

  final List<PracticeChar> chars;
  final PracticeGrid grid;

  /// Fuente del carácter modelo (Google Fonts).
  final String font;

  /// Cuántas copias tenues para calcar después del modelo.
  final int traceCount;
  final double cellSize;

  /// Mostrar pinyin y significado encima de cada fila.
  final bool showPinyin;

  PracticeSheet copyWith({List<PracticeChar>? chars}) => PracticeSheet(
        chars: chars ?? this.chars,
        grid: grid,
        font: font,
        traceCount: traceCount,
        cellSize: cellSize,
        showPinyin: showPinyin,
      );

  Map<String, Object?> toJson() => {
        'chars': chars.map((c) => c.toJson()).toList(),
        'grid': grid.name,
        'font': font,
        'trace': traceCount,
        'cell': cellSize,
        'pinyin': showPinyin,
      };

  factory PracticeSheet.fromJson(Map<String, Object?> j) => PracticeSheet(
        chars: [
          for (final c in (j['chars'] as List? ?? const []))
            PracticeChar.fromJson((c as Map).cast<String, Object?>()),
        ],
        grid: PracticeGrid.values.byName(j['grid'] as String? ?? 'tianzi'),
        font: j['font'] as String? ?? 'Ma Shan Zheng',
        traceCount: (j['trace'] as num?)?.toInt() ?? 3,
        cellSize: (j['cell'] as num?)?.toDouble() ?? 84,
        showPinyin: j['pinyin'] as bool? ?? true,
      );
}

/// Fuentes recomendadas para el carácter modelo.
const practiceFonts = <(String, String)>[
  ('Ma Shan Zheng', 'Regular con pincel (楷书) · recomendada'),
  ('Noto Serif SC', 'Impresa (宋体)'),
  ('Noto Sans SC', 'Sin adornos (黑体)'),
  ('Long Cang', 'A mano'),
  ('Zhi Mang Xing', 'Escritura corrida (行书)'),
];

/// Conjuntos de ejemplo para empezar a practicar.
class PracticeSet {
  const PracticeSet(this.name, this.chars);
  final String name;
  final List<PracticeChar> chars;
}

const practiceSets = <PracticeSet>[
  PracticeSet('Números', [
    PracticeChar('一', 'yī', 'uno'),
    PracticeChar('二', 'èr', 'dos'),
    PracticeChar('三', 'sān', 'tres'),
    PracticeChar('四', 'sì', 'cuatro'),
    PracticeChar('五', 'wǔ', 'cinco'),
    PracticeChar('六', 'liù', 'seis'),
    PracticeChar('七', 'qī', 'siete'),
    PracticeChar('八', 'bā', 'ocho'),
    PracticeChar('九', 'jiǔ', 'nueve'),
    PracticeChar('十', 'shí', 'diez'),
  ]),
  PracticeSet('Básicos', [
    PracticeChar('人', 'rén', 'persona'),
    PracticeChar('口', 'kǒu', 'boca'),
    PracticeChar('大', 'dà', 'grande'),
    PracticeChar('小', 'xiǎo', 'pequeño'),
    PracticeChar('山', 'shān', 'montaña'),
    PracticeChar('水', 'shuǐ', 'agua'),
    PracticeChar('火', 'huǒ', 'fuego'),
    PracticeChar('木', 'mù', 'árbol, madera'),
    PracticeChar('日', 'rì', 'sol, día'),
    PracticeChar('月', 'yuè', 'luna, mes'),
  ]),
  PracticeSet('Saludos', [
    PracticeChar('你', 'nǐ', 'tú'),
    PracticeChar('好', 'hǎo', 'bien, bueno'),
    PracticeChar('我', 'wǒ', 'yo'),
    PracticeChar('是', 'shì', 'ser'),
    PracticeChar('不', 'bù', 'no'),
    PracticeChar('谢', 'xiè', 'agradecer'),
    PracticeChar('再', 'zài', 'otra vez'),
    PracticeChar('见', 'jiàn', 'ver'),
  ]),
  PracticeSet('Familia', [
    PracticeChar('家', 'jiā', 'casa, familia'),
    PracticeChar('爸', 'bà', 'papá'),
    PracticeChar('妈', 'mā', 'mamá'),
    PracticeChar('哥', 'gē', 'hermano mayor'),
    PracticeChar('姐', 'jiě', 'hermana mayor'),
    PracticeChar('弟', 'dì', 'hermano menor'),
    PracticeChar('妹', 'mèi', 'hermana menor'),
  ]),
  PracticeSet('Colores', [
    PracticeChar('红', 'hóng', 'rojo'),
    PracticeChar('黄', 'huáng', 'amarillo'),
    PracticeChar('蓝', 'lán', 'azul'),
    PracticeChar('绿', 'lǜ', 'verde'),
    PracticeChar('白', 'bái', 'blanco'),
    PracticeChar('黑', 'hēi', 'negro'),
  ]),
  PracticeSet('Tiempo', [
    PracticeChar('年', 'nián', 'año'),
    PracticeChar('天', 'tiān', 'día, cielo'),
    PracticeChar('今', 'jīn', 'hoy, ahora'),
    PracticeChar('明', 'míng', 'claro; mañana'),
    PracticeChar('早', 'zǎo', 'temprano'),
    PracticeChar('时', 'shí', 'hora, tiempo'),
  ]),
];

/// Caracteres escritos por el usuario (sin pinyin ni significado).
List<PracticeChar> charsFromText(String text) => [
      for (final rune in text.runes)
        if (String.fromCharCode(rune).trim().isNotEmpty &&
            !',.;:!?，。、；：！？'.contains(String.fromCharCode(rune)))
          PracticeChar(String.fromCharCode(rune)),
    ];

/// Reparto de celdas en la hoja (filas × columnas, centradas).
class PracticeLayout {
  PracticeLayout(this.size, {required this.cellSize, required this.header, this.margin = 40}) {
    cols = math.max(1, ((size.width - margin * 2) / cellSize).floor());
    left = (size.width - cols * cellSize) / 2;
    rowHeight = header + cellSize + 6;
    rows = math.max(1, ((size.height - margin * 2) / rowHeight).floor());
  }

  final Size size;
  final double cellSize;
  final double header;
  final double margin;
  late final int cols;
  late final int rows;
  late final double left;
  late final double rowHeight;

  Rect cellRect(int row, int col) => Rect.fromLTWH(
        left + col * cellSize,
        margin + row * rowHeight + header,
        cellSize,
        cellSize,
      );
}
