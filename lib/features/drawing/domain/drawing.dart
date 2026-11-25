import 'dart:ui';

/// Herramientas de dibujo. Cada una se ve distinta (ver `stroke_renderer.dart`).
enum ToolType {
  pen('Bolígrafo'),
  pencil('Lápiz'),
  brush('Pincel'),
  marker('Marcador'),
  highlighter('Resaltador'),
  eraser('Borrador');

  const ToolType(this.label);
  final String label;
}

/// Hojas disponibles (como las plantillas de StarNote/Freenotes).
enum PaperTemplate {
  blank('En blanco'),
  lined('Rayada'),
  grid('Cuadriculada'),
  dots('Puntos'),
  cornell('Cornell'),
  todo('Lista de tareas'),
  music('Pentagrama');

  const PaperTemplate(this.label);
  final String label;
}

/// Un punto del trazo. [p] es la presión (0–1) o null si no se conoce
/// (dedo): en ese caso se simula por la velocidad.
class StrokePoint {
  const StrokePoint(this.x, this.y, [this.p]);
  final double x;
  final double y;
  final double? p;
}

class Stroke {
  Stroke({
    required this.tool,
    required this.color,
    required this.size,
    required this.points,
  });

  final ToolType tool;

  /// Color ARGB (0xAARRGGBB).
  final int color;
  final double size;
  final List<StrokePoint> points;

  /// Caché del dibujo ya calculado (no se guarda en el archivo).
  Path? cachedPath;

  Rect get bounds {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final pt in points) {
      if (pt.x < minX) minX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y > maxY) maxY = pt.y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(size);
  }

  Map<String, Object?> toJson() => {
        't': tool.name,
        'c': color,
        's': size,
        // Formato compacto: [x, y, p, x, y, p, ...] con 1 decimal.
        'pts': [
          for (final pt in points) ...[
            _r(pt.x),
            _r(pt.y),
            pt.p == null ? -1 : _r(pt.p!, 100),
          ],
        ],
      };

  factory Stroke.fromJson(Map<String, Object?> j) {
    final raw = (j['pts']! as List).cast<num>();
    return Stroke(
      tool: ToolType.values.byName(j['t']! as String),
      color: j['c']! as int,
      size: (j['s']! as num).toDouble(),
      points: [
        for (var i = 0; i + 2 < raw.length; i += 3)
          StrokePoint(
            raw[i].toDouble(),
            raw[i + 1].toDouble(),
            raw[i + 2] < 0 ? null : raw[i + 2].toDouble(),
          ),
      ],
    );
  }

  static double _r(double v, [int f = 10]) => (v * f).roundToDouble() / f;
}

class DrawingLayer {
  const DrawingLayer({
    required this.id,
    required this.name,
    this.visible = true,
    this.locked = false,
    this.opacity = 1,
    this.strokes = const [],
  });

  final String id;
  final String name;
  final bool visible;
  final bool locked;
  final double opacity;
  final List<Stroke> strokes;

  DrawingLayer copyWith({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    List<Stroke>? strokes,
  }) =>
      DrawingLayer(
        id: id,
        name: name ?? this.name,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        opacity: opacity ?? this.opacity,
        strokes: strokes ?? this.strokes,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'visible': visible,
        'locked': locked,
        'opacity': opacity,
        'strokes': strokes.map((s) => s.toJson()).toList(),
      };

  factory DrawingLayer.fromJson(Map<String, Object?> j) => DrawingLayer(
        id: j['id']! as String,
        name: j['name']! as String,
        visible: j['visible'] as bool? ?? true,
        locked: j['locked'] as bool? ?? false,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1,
        strokes: [
          for (final s in (j['strokes'] as List? ?? const []))
            Stroke.fromJson((s as Map).cast<String, Object?>()),
        ],
      );
}

class PaperStyle {
  const PaperStyle({
    this.template = PaperTemplate.lined,
    this.background = 0xFFFFFFFF,
    this.spacing = 40,
    this.imagePath,
  });

  final PaperTemplate template;
  final int background;

  /// Hoja personalizada: imagen subida por el usuario como fondo.
  final String? imagePath;

  /// Separación entre renglones / cuadros.
  final double spacing;

  bool get isDark => Color(background).computeLuminance() < 0.3;

  PaperStyle copyWith({
    PaperTemplate? template,
    int? background,
    double? spacing,
    String? imagePath,
    bool clearImage = false,
  }) =>
      PaperStyle(
        template: template ?? this.template,
        background: background ?? this.background,
        spacing: spacing ?? this.spacing,
        imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      );

  Map<String, Object?> toJson() => {
        'template': template.name,
        'background': background,
        'spacing': spacing,
        if (imagePath != null) 'image': imagePath,
      };

  factory PaperStyle.fromJson(Map<String, Object?> j) => PaperStyle(
        template: PaperTemplate.values.byName(j['template'] as String? ?? 'lined'),
        background: j['background'] as int? ?? 0xFFFFFFFF,
        spacing: (j['spacing'] as num?)?.toDouble() ?? 40,
        imagePath: j['image'] as String?,
      );
}

/// Una hoja de dibujo/escritura a mano, con capas.
class Drawing {
  const Drawing({
    required this.width,
    required this.height,
    required this.paper,
    required this.layers,
    this.bookmarked = false,
  });

  /// Tamaño A4 vertical en unidades lógicas.
  static const a4Width = 1000.0;
  static const a4Height = 1414.0;

  factory Drawing.blank({PaperStyle paper = const PaperStyle()}) => Drawing(
        width: a4Width,
        height: a4Height,
        paper: paper,
        layers: const [DrawingLayer(id: 'l1', name: 'Capa 1')],
      );

  final double width;
  final double height;
  final PaperStyle paper;
  final List<DrawingLayer> layers;

  /// Página marcada (aparece con 🔖 en las miniaturas).
  final bool bookmarked;

  bool get isLandscape => width > height;

  Drawing copyWith({
    double? width,
    double? height,
    PaperStyle? paper,
    List<DrawingLayer>? layers,
    bool? bookmarked,
  }) =>
      Drawing(
        width: width ?? this.width,
        height: height ?? this.height,
        paper: paper ?? this.paper,
        layers: layers ?? this.layers,
        bookmarked: bookmarked ?? this.bookmarked,
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'w': width,
        'h': height,
        'paper': paper.toJson(),
        if (bookmarked) 'bookmarked': true,
        'layers': layers.map((l) => l.toJson()).toList(),
      };

  factory Drawing.fromJson(Map<String, Object?> j) => Drawing(
        width: (j['w'] as num?)?.toDouble() ?? a4Width,
        height: (j['h'] as num?)?.toDouble() ?? a4Height,
        paper: PaperStyle.fromJson((j['paper'] as Map? ?? const {}).cast<String, Object?>()),
        bookmarked: j['bookmarked'] as bool? ?? false,
        layers: [
          for (final l in (j['layers'] as List? ?? const []))
            DrawingLayer.fromJson((l as Map).cast<String, Object?>()),
        ],
      );
}
