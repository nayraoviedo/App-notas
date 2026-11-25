class Notebook {
  const Notebook({
    required this.id,
    required this.name,
    required this.color,
    this.coverPath,
  });

  final String id;
  final String name;
  final int color;
  final String? coverPath;
}

/// Colores de portada disponibles.
const notebookColors = <int>[
  0xFF1677FF, 0xFF12A594, 0xFF30A46C, 0xFFFFB224, 0xFFE5484D,
  0xFFD6409F, 0xFF6E56CF, 0xFF5C6370, 0xFF8D6E63, 0xFF1F2328,
];
