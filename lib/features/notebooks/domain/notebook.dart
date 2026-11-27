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
  checker('Damero'),
  sageFlowers('Florecitas'),
  blueTrellis('Jardín azul'),
  tulipChecker('Tulipanes'),
  starryCat('Estrellas');

  const CoverPattern(this.label);
  final String label;

  /// Portadas ilustradas (llevan placa central con el título).
  bool get isIllustrated => index >= CoverPattern.sageFlowers.index;

  /// Color de fondo que mejor le queda (null = el que elija la persona).
  int? get preferredColor => switch (this) {
        CoverPattern.sageFlowers => 0xFFB6C4A2,
        CoverPattern.blueTrellis => 0xFFFAFBFD,
        CoverPattern.tulipChecker => 0xFFF6F0E4,
        CoverPattern.starryCat => 0xFFF1EBE3,
        _ => null,
      };
}

/// Obras de dominio público para usar como portada.
class CoverArt {
  const CoverArt(this.asset, this.title, this.artist);
  final String asset;
  final String title;
  final String artist;
}

const coverArts = <CoverArt>[
  CoverArt('assets/covers/almendro.jpg', 'Almendro en flor (1890)', 'Vincent van Gogh'),
  CoverArt('assets/covers/ciruelos.jpg', 'Ciruelos en flor (1887)', 'Vincent van Gogh'),
  CoverArt('assets/covers/huerto.jpg', 'Huerto en flor (1888)', 'Vincent van Gogh'),
  CoverArt('assets/covers/nenufares.jpg', 'Nenúfares (1906)', 'Claude Monet'),
  CoverArt('assets/covers/estanque.jpg', 'Estanque con nenúfares', 'Claude Monet'),
  CoverArt('assets/covers/ola.jpg', 'La gran ola (1831)', 'Katsushika Hokusai'),
  CoverArt('assets/covers/fresas.jpg', 'Ladrón de fresas (1883)', 'William Morris'),
];

/// Diseño de portada: patrón + sticker (emoji). Se guarda como "patrón;emoji".
class CoverStyle {
  const CoverStyle({this.pattern = CoverPattern.dots, this.sticker = '🌸', this.plate, this.art});

  final CoverPattern pattern;

  /// Sticker de la portada ('' = ninguno).
  final String sticker;

  /// Texto de la placa central (null = el nombre del cuaderno).
  final String? plate;

  /// Obra de arte de dominio público usada de fondo (ruta del asset).
  final String? art;

  /// ¿Lleva la placa central "NOTEBOOK"?
  bool get hasPlate => pattern.isIllustrated || art != null || (plate?.isNotEmpty ?? false);

  String encode() =>
      '${pattern.name};$sticker;${(plate ?? '').replaceAll(';', ',')};${art ?? ''}';

  factory CoverStyle.decode(String? s) {
    if (s == null || s.isEmpty) return const CoverStyle(pattern: CoverPattern.plain, sticker: '');
    final parts = s.split(';');
    return CoverStyle(
      pattern: CoverPattern.values.where((p) => p.name == parts.first).firstOrNull ??
          CoverPattern.plain,
      sticker: parts.length > 1 ? parts[1] : '',
      plate: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
      art: parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null,
    );
  }

  CoverStyle copyWith({
    CoverPattern? pattern,
    String? sticker,
    String? plate,
    bool clearPlate = false,
    String? art,
    bool clearArt = false,
  }) =>
      CoverStyle(
        pattern: pattern ?? this.pattern,
        sticker: sticker ?? this.sticker,
        plate: clearPlate ? null : (plate ?? this.plate),
        art: clearArt ? null : (art ?? this.art),
      );
}

/// Colores de portada: pasteles primero y algunos más intensos.
const notebookColors = <int>[
  0xFFFFC8DD, 0xFFFFAFCC, 0xFFCDB4DB, 0xFFBDE0FE, 0xFFA2D2FF,
  0xFFB9FBC0, 0xFFFDFFB6, 0xFFFFD6A5, 0xFFFFADAD, 0xFFE9EDC9,
  0xFF1677FF, 0xFF12A594, 0xFFE5484D, 0xFF6E56CF, 0xFF1F2328,
];

/// Stickers para la portada.
/// "cat:orange" y "cat:gray" son las mascotas dibujadas por la app.
final coverStickers = <String>[
  '', 'cat:orange', 'cat:gray',
  // Los stickers de gatitos dibujados (assets/stickers/cat_01…27.png).
  for (var i = 1; i <= 27; i++) 'assets/stickers/cat_${i < 10 ? '0$i' : '$i'}.png',
  // Doodles dibujados a mano ("doodle:<id>").
  for (final d in ['heart', 'star', 'sparkles', 'cloud', 'sun', 'flower', 'moon', 'crown', 'bow', 'leaves',
      'book', 'bulb', 'coffee', 'music', 'paw', 'rainbow', 'cat', 'hearts'])
    'doodle:doodle_$d',
];
