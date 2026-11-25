import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';

import '../../domain/drawing.dart';

/// Cómo se ve cada herramienta.
///
/// - Bolígrafo: línea firme, casi sin variación de grosor.
/// - Lápiz: fino, algo transparente y con borde suave (grafito).
/// - Pincel: muy sensible a la presión, con puntas afinadas.
/// - Marcador: grueso y opaco.
/// - Resaltador: plano, translúcido y "multiplica" el color (no tapa).
/// - Borrador: borra píxeles solo de la capa activa.
class StrokeRenderer {
  static void paint(Canvas canvas, Stroke stroke, {bool live = false}) {
    if (stroke.points.isEmpty) return;
    final color = Color(stroke.color);

    switch (stroke.tool) {
      case ToolType.highlighter:
        canvas.drawPath(
          _polyline(stroke),
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke.size
            ..strokeCap = StrokeCap.square
            ..strokeJoin = StrokeJoin.round
            ..blendMode = BlendMode.multiply,
        );
      case ToolType.eraser:
        canvas.drawPath(
          _outline(stroke, live),
          Paint()..blendMode = BlendMode.clear,
        );
      case ToolType.pencil:
        canvas.drawPath(
          _outline(stroke, live),
          Paint()
            ..color = color.withValues(alpha: 0.8)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
        );
      case ToolType.pen:
      case ToolType.brush:
      case ToolType.marker:
        canvas.drawPath(_outline(stroke, live), Paint()..color = color);
    }
  }

  /// Contorno calculado con perfect_freehand (se guarda en caché al terminar).
  static Path _outline(Stroke s, bool live) {
    if (!live && s.cachedPath != null) return s.cachedPath!;
    final hasPressure = s.points.any((pt) => pt.p != null);
    final outline = getStroke(
      [for (final pt in s.points) PointVector(pt.x, pt.y, pt.p)],
      options: _options(s, hasPressure, live),
    );
    final path = Path()..addPolygon(outline, true);
    if (!live) s.cachedPath = path;
    return path;
  }

  static Path _polyline(Stroke s) {
    if (s.cachedPath != null) return s.cachedPath!;
    final path = Path()..moveTo(s.points.first.x, s.points.first.y);
    for (final pt in s.points.skip(1)) {
      path.lineTo(pt.x, pt.y);
    }
    if (s.points.length == 1) path.lineTo(s.points.first.x + 0.1, s.points.first.y);
    return path; // se recalcula en vivo; barato
  }

  static StrokeOptions _options(Stroke s, bool hasPressure, bool live) {
    final simulate = !hasPressure;
    switch (s.tool) {
      case ToolType.pen:
        return StrokeOptions(
          size: s.size,
          thinning: 0.15,
          smoothing: 0.6,
          streamline: 0.5,
          simulatePressure: simulate,
          isComplete: !live,
        );
      case ToolType.pencil:
        return StrokeOptions(
          size: s.size,
          thinning: 0.35,
          smoothing: 0.4,
          streamline: 0.35,
          simulatePressure: simulate,
          isComplete: !live,
        );
      case ToolType.brush:
        return StrokeOptions(
          size: s.size,
          thinning: 0.8,
          smoothing: 0.7,
          streamline: 0.6,
          simulatePressure: simulate,
          start: StrokeEndOptions.start(taperEnabled: true, customTaper: s.size * 2),
          end: StrokeEndOptions.end(taperEnabled: true, customTaper: s.size * 2),
          isComplete: !live,
        );
      case ToolType.marker:
      case ToolType.eraser:
      case ToolType.highlighter:
        return StrokeOptions(
          size: s.size,
          thinning: 0,
          smoothing: 0.5,
          streamline: 0.5,
          simulatePressure: false,
          isComplete: !live,
        );
    }
  }
}
