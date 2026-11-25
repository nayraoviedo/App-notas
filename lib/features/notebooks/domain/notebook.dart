class Notebook {
  const Notebook({
    required this.id,
    required this.name,
    required this.color,
    this.coverPath,
    this.style = const CoverStyle(),
  });

  final String id;
  final String name;
  final int color;
  final String? coverPath;
  final CoverStyle style;
}

/// Dibujos para portadas "cute".
enum CoverPattern {
  plain('Liso'),
  dots('Lunares'),
  gingham('Cuadritos'),
  stripes('Rayas'),
  hearts('Corazones'),
  stars('Estrellas'),
  clouds('Nubes'),
  checker('Damero');

  const CoverPattern(this.label);
  final String label;
}

/// Diseño de portada: patrón + sticker (emoji). Se guarda como "patrón;emoji".
class CoverStyle {
  const CoverStyle({this.pattern = CoverPattern.dots, this.sticker = '🌸'});

  final CoverPattern pattern;

  /// Sticker de la portada ('' = ninguno).
  final String sticker;

  String encode() => '${pattern.name};$sticker';

  factory CoverStyle.decode(String? s) {
    if (s == null || s.isEmpty) return const CoverStyle(pattern: CoverPattern.plain, sticker: '');
    final parts = s.split(';');
    return CoverStyle(
      pattern: CoverPattern.values.where((p) => p.name == parts.first).firstOrNull ??
          CoverPattern.plain,
      sticker: parts.length > 1 ? parts[1] : '',
    );
  }

  CoverStyle copyWith({CoverPattern? pattern, String? sticker}) =>
      CoverStyle(pattern: pattern ?? this.pattern, sticker: sticker ?? this.sticker);
}

/// Colores de portada: pasteles primero y algunos más intensos.
const notebookColors = <int>[
  0xFFFFC8DD, 0xFFFFAFCC, 0xFFCDB4DB, 0xFFBDE0FE, 0xFFA2D2FF,
  0xFFB9FBC0, 0xFFFDFFB6, 0xFFFFD6A5, 0xFFFFADAD, 0xFFE9EDC9,
  0xFF1677FF, 0xFF12A594, 0xFFE5484D, 0xFF6E56CF, 0xFF1F2328,
];

/// Stickers para la portada.
const coverStickers = <String>[
  '', '🌸', '🎀', '⭐', '🍓', '🐱', '🐻', '☁️', '🌙', '🌷', '🍀', '📚', '✏️', '🎧', '🧸', '💌',
];
