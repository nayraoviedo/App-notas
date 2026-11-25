/// Elementos que se ponen encima de la hoja (estilo collage): textos y fotos.
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
  });

  final String text;

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
      );

  @override
  Map<String, Object?> toJson() => {
        ...baseJson('text'),
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
  });

  final String path;

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
      );

  @override
  Map<String, Object?> toJson() => {
        ...baseJson('image'),
        'path': path,
        'w': width,
        'h': height,
        if (frame != ImageFrame.none) 'frame': frame.name,
      };
}
