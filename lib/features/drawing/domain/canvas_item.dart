/// Elementos que se ponen encima de la hoja (estilo collage): textos, fotos,
/// stickers y formas.
/// Se pueden mover, agrandar y girar. Viven dentro de una capa, así que
/// respetan el orden de las capas.
sealed class CanvasItem {
  const CanvasItem({
    required this.id,
    required this.x,
    required this.y,
    this.scale = 1,
    this.rotation = 0,
  });

  final String id;

  /// Centro del elemento en coordenadas de la hoja.
  final double x;
  final double y;
  final double scale;

  /// Radianes.
  final double rotation;

  CanvasItem moved({double? x, double? y, double? scale, double? rotation});

  Map<String, Object?> toJson();

  Map<String, Object?> baseJson(String kind) => {
        'k': kind,
        'id': id,
        'x': x,
        'y': y,
        if (scale != 1) 's': scale,
        if (rotation != 0) 'r': rotation,
      };

  static CanvasItem? fromJson(Map<String, Object?> j) {
    final id = j['id']! as String;
    final x = (j['x'] as num).toDouble();
    final y = (j['y'] as num).toDouble();
    final s = (j['s'] as num?)?.toDouble() ?? 1;
    final r = (j['r'] as num?)?.toDouble() ?? 0;
    switch (j['k']) {
      case 'text':
        return TextItem(
          id: id,
          x: x,
          y: y,
          scale: s,
          rotation: r,
          text: j['text'] as String? ?? '',
          font: j['font'] as String?,
          size: (j['size'] as num?)?.toDouble() ?? 32,
          color: j['color'] as int? ?? 0xFF1F2328,
          bold: j['bold'] as bool? ?? false,
          italic: j['italic'] as bool? ?? false,
          align: TextItemAlign.values.byName(j['align'] as String? ?? 'left'),
          background: j['bg'] as int?,
          width: (j['w'] as num?)?.toDouble() ?? 500,
          lineHeight: (j['lh'] as num?)?.toDouble() ?? 1.25,
          underline: j['u'] as bool? ?? false,
          strike: j['strk'] as bool? ?? false,
        );
      case 'image':
        return ImageItem(
          id: id,
          x: x,
          y: y,
          scale: s,
          rotation: r,
          path: j['path']! as String,
          width: (j['w'] as num).toDouble(),
          height: (j['h'] as num).toDouble(),
          frame: ImageFrame.values.byName(j['frame'] as String? ?? 'none'),
          source: j['src'] as String?,
        );
      case 'sticker':
        return StickerItem(
          id: id,
          x: x,
          y: y,
          scale: s,
          rotation: r,
          sticker: j['st']! as String,
          width: (j['w'] as num?)?.toDouble() ?? 200,
          height: (j['h'] as num?)?.toDouble() ?? 200,
        );
      case 'shape':
        final kind = ShapeKind.values.where((k) => k.name == j['sh']).firstOrNull;
        if (kind == null) return null;
        return ShapeItem(
          id: id,
          x: x,
          y: y,
          scale: s,
          rotation: r,
          shape: kind,
          width: (j['w'] as num?)?.toDouble() ?? 200,
          height: (j['h'] as num?)?.toDouble() ?? 200,
          color: j['color'] as int? ?? 0xFF1F2328,
          strokeWidth: (j['sw'] as num?)?.toDouble() ?? 4,
          fill: j['fill'] as int?,
        );
    }
    return null;
  }
}

enum TextItemAlign { left, center, right }

class TextItem extends CanvasItem {
  const TextItem({
    required super.id,
    required super.x,
    required super.y,
    super.scale,
    super.rotation,
    required this.text,
    this.font,
    this.size = 32,
    this.color = 0xFF1F2328,
    this.bold = false,
    this.italic = false,
    this.align = TextItemAlign.left,
    this.background,
    this.width = 500,
    this.lineHeight = 1.25,
    this.underline = false,
    this.strike = false,
  });

  final bool underline;

  /// Tachado.
  final bool strike;

  final String text;

  /// Interlineado (1.0×, 1.25×, 1.5×…).
  final double lineHeight;

  /// Fuente de Google Fonts (null = del sistema).
  final String? font;
  final double size;
  final int color;
  final bool bold;
  final bool italic;
  final TextItemAlign align;

  /// Fondo tipo etiqueta o cinta (null = transparente).
  final int? background;

  /// Ancho máximo del cuadro de texto (en coordenadas de la hoja).
  final double width;

  @override
  TextItem moved({double? x, double? y, double? scale, double? rotation}) => copyWith(
        x: x,
        y: y,
        scale: scale,
        rotation: rotation,
      );

  TextItem copyWith({
    double? x,
    double? y,
    double? scale,
    double? rotation,
    String? text,
    String? font,
    bool clearFont = false,
    double? size,
    int? color,
    bool? bold,
    bool? italic,
    TextItemAlign? align,
    int? background,
    bool clearBackground = false,
    double? width,
    double? lineHeight,
    bool? underline,
    bool? strike,
  }) =>
      TextItem(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        text: text ?? this.text,
        font: clearFont ? null : (font ?? this.font),
        size: size ?? this.size,
        color: color ?? this.color,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        align: align ?? this.align,
        background: clearBackground ? null : (background ?? this.background),
        width: width ?? this.width,
        lineHeight: lineHeight ?? this.lineHeight,
        underline: underline ?? this.underline,
        strike: strike ?? this.strike,
      );

  @override
  Map<String, Object?> toJson() => {
        ...baseJson('text'),
        if (lineHeight != 1.25) 'lh': lineHeight,
        if (underline) 'u': true,
        if (strike) 'strk': true,
        'text': text,
        if (font != null) 'font': font,
        'size': size,
        'color': color,
        if (bold) 'bold': true,
        if (italic) 'italic': true,
        if (align != TextItemAlign.left) 'align': align.name,
        if (background != null) 'bg': background,
        'w': width,
      };
}

/// Marco decorativo para fotos del collage.
enum ImageFrame {
  none('Sin marco'),
  polaroid('Polaroid'),
  rounded('Redondeada'),
  tape('Con cinta');

  const ImageFrame(this.label);
  final String label;
}

class ImageItem extends CanvasItem {
  const ImageItem({
    required super.id,
    required super.x,
    required super.y,
    super.scale,
    super.rotation,
    required this.path,
    required this.width,
    required this.height,
    this.frame = ImageFrame.none,
    this.source,
  });

  final String path;

  /// Si la imagen es una tabla o ecuación hecha en la app: sus datos (JSON)
  /// para poder volver a editarla. null en fotos.
  final String? source;

  /// Tamaño base (con escala 1) en coordenadas de la hoja.
  final double width;
  final double height;
  final ImageFrame frame;

  @override
  ImageItem moved({double? x, double? y, double? scale, double? rotation}) => ImageItem(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        path: path,
        width: width,
        height: height,
        frame: frame,
        source: source,
      );

  ImageItem withFrame(ImageFrame f) => ImageItem(
        id: id,
        x: x,
        y: y,
        scale: scale,
        rotation: rotation,
        path: path,
        width: width,
        height: height,
        frame: f,
        source: source,
      );

  @override
  Map<String, Object?> toJson() => {
        ...baseJson('image'),
        'path': path,
        'w': width,
        'h': height,
        if (frame != ImageFrame.none) 'frame': frame.name,
        if (source != null) 'src': source,
      };
}

/// Sticker dibujado por la app (notas adhesivas, cintas, flores…). Ver
/// `sticker_painter.dart` para el catálogo.
class StickerItem extends CanvasItem {
  const StickerItem({
    required super.id,
    required super.x,
    required super.y,
    super.scale,
    super.rotation,
    required this.sticker,
    this.width = 200,
    this.height = 200,
  });

  /// Identificador del sticker en el catálogo (por ejemplo "memo_heart").
  final String sticker;
  final double width;
  final double height;

  @override
  StickerItem moved({double? x, double? y, double? scale, double? rotation}) => StickerItem(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        sticker: sticker,
        width: width,
        height: height,
      );

  @override
  Map<String, Object?> toJson() => {
        ...baseJson('sticker'),
        'st': sticker,
        'w': width,
        'h': height,
      };
}

/// Formas del panel "Forma" (líneas, flechas, figuras).
enum ShapeKind {
  line('Línea'),
  wavy('Ondulada'),
  curve('Curva'),
  dashed('Punteada'),
  arrow('Flecha'),
  doubleArrow('Flecha doble'),
  curveArrow('Flecha curva'),
  angle('Ángulo'),
  axes('Ejes'),
  axes3d('Ejes 3D'),
  brace('Llave'),
  triangle('Triángulo'),
  isoTriangle('Isósceles'),
  rightTriangle('Rectángulo'),
  square('Cuadrado'),
  rectangle('Rectángulo'),
  roundedRect('Redondeado'),
  pill('Píldora'),
  trapezoid('Trapecio'),
  parallelogram('Paralelogramo'),
  circle('Círculo'),
  ellipse('Elipse'),
  diamond('Rombo'),
  pentagon('Pentágono'),
  hexagon('Hexágono'),
  star('Estrella'),
  heart('Corazón'),
  bubble('Globo de diálogo'),
  cloud('Nube'),
  cube('Cubo'),
  cylinder('Cilindro'),
  cone('Cono');

  const ShapeKind(this.label);
  final String label;

  /// Las líneas no se rellenan.
  bool get isLine => index <= ShapeKind.brace.index;

  /// Tamaño inicial (ancho, alto) al ponerla en la hoja.
  (double, double) get defaultSize => switch (this) {
        ShapeKind.line || ShapeKind.dashed || ShapeKind.arrow || ShapeKind.doubleArrow => (260, 24),
        ShapeKind.wavy => (260, 40),
        ShapeKind.curve || ShapeKind.curveArrow => (240, 90),
        ShapeKind.brace => (60, 220),
        ShapeKind.rectangle || ShapeKind.roundedRect || ShapeKind.ellipse => (280, 180),
        ShapeKind.pill || ShapeKind.parallelogram || ShapeKind.trapezoid => (280, 140),
        ShapeKind.bubble || ShapeKind.cloud => (260, 190),
        _ => (200, 200),
      };
}

class ShapeItem extends CanvasItem {
  const ShapeItem({
    required super.id,
    required super.x,
    required super.y,
    super.scale,
    super.rotation,
    required this.shape,
    this.width = 200,
    this.height = 200,
    this.color = 0xFF1F2328,
    this.strokeWidth = 4,
    this.fill,
  });

  final ShapeKind shape;
  final double width;
  final double height;
  final int color;
  final double strokeWidth;

  /// Color de relleno (null = sin relleno).
  final int? fill;

  @override
  ShapeItem moved({double? x, double? y, double? scale, double? rotation}) =>
      copyWith(x: x, y: y, scale: scale, rotation: rotation);

  ShapeItem copyWith({
    double? x,
    double? y,
    double? scale,
    double? rotation,
    double? width,
    double? height,
    int? color,
    double? strokeWidth,
    int? fill,
    bool clearFill = false,
  }) =>
      ShapeItem(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        shape: shape,
        width: width ?? this.width,
        height: height ?? this.height,
        color: color ?? this.color,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        fill: clearFill ? null : (fill ?? this.fill),
      );

  @override
  Map<String, Object?> toJson() => {
        ...baseJson('shape'),
        'sh': shape.name,
        'w': width,
        'h': height,
        'color': color,
        'sw': strokeWidth,
        if (fill != null) 'fill': fill,
      };
}
