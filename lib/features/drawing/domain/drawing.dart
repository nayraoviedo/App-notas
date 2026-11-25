import 'dart:ui';

import 'canvas_item.dart';
import 'practice.dart';

export 'canvas_item.dart';

/// Herramientas de dibujo. Cada una se ve distinta (ver `stroke_renderer.dart`).
enum ToolType {
  pen('Bolígrafo'),
  fountain('Pluma estilográfica'),
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
  linedNarrow('Línea estrecha'),
  linedWide('Línea ancha'),
  grid('Cuadriculada'),
  miniGrid('Mini cuadrícula'),
  dots('Puntos'),
  cornell('Cornell A'),
  cornellB('Cornell B'),
  cornellC('Cornell C'),
  ebbinghaus('Repaso Ebbinghaus'),
  todo('Lista de tareas'),
  dailyPlan('Plan diario'),
  weeklyPlan('Plan semanal'),
  habits('Hábitos mensuales'),
  reading('Registro de lectura'),
  englishLines('Papel de inglés'),
  music('Pentagrama'),
  guitarTab('Tablatura'),
  soccer('Cancha de fútbol'),
  basketball('Cancha de básquet'),
  cover('Tapa'),
  tianzi('田字格 Tianzi'),
  mizi('米字格 Mizi'),
  jiugong('九宫格 Nueve casillas');

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
    this.thinning,
    this.streamline,
  });

  final ToolType tool;

  /// Sensibilidad a la presión (0–1) y estabilización del trazo (0–1).
  /// null = el valor propio de la herramienta.
  final double? thinning;
  final double? streamline;

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
        if (thinning != null) 'th': _r(thinning!, 100),
        if (streamline != null) 'sl': _r(streamline!, 100),
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
      tool: ToolType.values.where((t) => t.name == j['t']).firstOrNull ?? ToolType.pen,
      color: j['c']! as int,
      size: (j['s']! as num).toDouble(),
      thinning: (j['th'] as num?)?.toDouble(),
      streamline: (j['sl'] as num?)?.toDouble(),
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
    this.items = const [],
  });

  final String id;
  final String name;
  final bool visible;
  final bool locked;
  final double opacity;
  final List<Stroke> strokes;

  /// Textos y fotos del collage, encima de los trazos de esta capa.
  final List<CanvasItem> items;

  DrawingLayer copyWith({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    List<Stroke>? strokes,
    List<CanvasItem>? items,
  }) =>
      DrawingLayer(
        id: id,
        name: name ?? this.name,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        opacity: opacity ?? this.opacity,
        strokes: strokes ?? this.strokes,
        items: items ?? this.items,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        if (items.isNotEmpty) 'items': items.map((i) => i.toJson()).toList(),
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
        items: (j['items'] as List? ?? const [])
            .map((i) => CanvasItem.fromJson((i as Map).cast<String, Object?>()))
            .nonNulls
            .toList(),
      );
}

class PaperStyle {
  const PaperStyle({
    this.template = PaperTemplate.lined,
    this.background = 0xFFFFFFFF,
    this.spacing = 40,
    this.imagePath,
    this.practice,
    this.design,
  });

  final PaperTemplate template;

  /// Tapa ilustrada (nombre del dibujo, por ejemplo "sageFlowers").
  final String? design;

  /// Hoja de práctica de caligrafía china (caracteres modelo para calcar).
  final PracticeSheet? practice;
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
    PracticeSheet? practice,
    bool clearPractice = false,
    String? design,
    bool clearDesign = false,
  }) =>
      PaperStyle(
        design: clearDesign ? null : (design ?? this.design),
        template: template ?? this.template,
        background: background ?? this.background,
        spacing: spacing ?? this.spacing,
        imagePath: clearImage ? null : (imagePath ?? this.imagePath),
        practice: clearPractice ? null : (practice ?? this.practice),
      );

  Map<String, Object?> toJson() => {
        'template': template.name,
        'background': background,
        'spacing': spacing,
        if (imagePath != null) 'image': imagePath,
        if (practice != null) 'practice': practice!.toJson(),
        if (design != null) 'design': design,
      };

  factory PaperStyle.fromJson(Map<String, Object?> j) => PaperStyle(
        template: PaperTemplate.values.where((t) => t.name == j['template']).firstOrNull ??
            PaperTemplate.lined,
        background: j['background'] as int? ?? 0xFFFFFFFF,
        spacing: (j['spacing'] as num?)?.toDouble() ?? 40,
        imagePath: j['image'] as String?,
        design: j['design'] as String?,
        practice: j['practice'] == null
            ? null
            : PracticeSheet.fromJson((j['practice'] as Map).cast<String, Object?>()),
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
    this.tab,
    this.tabColor,
  });

  /// Pestaña al costado del cuaderno (como un separador), o null.
  final String? tab;
  final int? tabColor;

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
    String? tab,
    int? tabColor,
    bool clearTab = false,
  }) =>
      Drawing(
        width: width ?? this.width,
        height: height ?? this.height,
        paper: paper ?? this.paper,
        layers: layers ?? this.layers,
        bookmarked: bookmarked ?? this.bookmarked,
        tab: clearTab ? null : (tab ?? this.tab),
        tabColor: clearTab ? null : (tabColor ?? this.tabColor),
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'w': width,
        'h': height,
        'paper': paper.toJson(),
        if (bookmarked) 'bookmarked': true,
        if (tab != null) 'tab': tab,
        if (tabColor != null) 'tabColor': tabColor,
        'layers': layers.map((l) => l.toJson()).toList(),
      };

  factory Drawing.fromJson(Map<String, Object?> j) => Drawing(
        width: (j['w'] as num?)?.toDouble() ?? a4Width,
        height: (j['h'] as num?)?.toDouble() ?? a4Height,
        paper: PaperStyle.fromJson((j['paper'] as Map? ?? const {}).cast<String, Object?>()),
        bookmarked: j['bookmarked'] as bool? ?? false,
        tab: j['tab'] as String?,
        tabColor: j['tabColor'] as int?,
        layers: [
          for (final l in (j['layers'] as List? ?? const []))
            DrawingLayer.fromJson((l as Map).cast<String, Object?>()),
        ],
      );
}
