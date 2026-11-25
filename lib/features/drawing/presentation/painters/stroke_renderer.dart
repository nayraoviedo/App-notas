import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show Colors;

import 'package:perfect_freehand/perfect_freehand.dart';

import '../../domain/drawing.dart';

/// Cómo se ve cada herramienta.
///
/// - Bolígrafo: línea firme, casi sin variación de grosor.
/// - Pluma estilográfica: tinta con trazo que engrosa con la presión.
/// - Lápiz: fino, algo transparente y con borde suave (grafito).
/// - Pincel: muy sensible a la presión, con puntas afinadas.
/// - Marcador: grueso y opaco.
/// - Resaltador: plano, translúcido y "multiplica" el color (no tapa).
/// - Borrador: borra píxeles solo de la capa activa.
class StrokeRenderer {
  /// Mezcla del resaltador (se toma de Ajustes).
  static BlendMode highlighterBlend = BlendMode.multiply;

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
            ..blendMode = highlighterBlend,
        );
      case ToolType.tape:
        paintTape(canvas, stroke);
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
      case ToolType.fountain:
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
    // Valores propios de cada herramienta: (presión, suavizado, estabilización).
    final (thinning, smoothing, streamline) = switch (s.tool) {
      ToolType.pen => (0.15, 0.6, 0.5),
      ToolType.fountain => (0.55, 0.65, 0.5),
      ToolType.pencil => (0.35, 0.4, 0.35),
      ToolType.brush => (0.8, 0.7, 0.6),
      ToolType.marker || ToolType.eraser || ToolType.highlighter || ToolType.tape => (0.0, 0.5, 0.5),
    };
    final flat = s.tool == ToolType.marker ||
        s.tool == ToolType.eraser ||
        s.tool == ToolType.highlighter;
    final tapered = s.tool == ToolType.brush || s.tool == ToolType.fountain;
    final taper = s.tool == ToolType.brush ? s.size * 2 : s.size * 0.8;
    final th = flat ? 0.0 : (s.thinning ?? thinning);
    final sl = s.streamline ?? streamline;
    final sim = flat ? false : simulate;
    if (tapered) {
      return StrokeOptions(
        size: s.size,
        thinning: th,
        smoothing: smoothing,
        streamline: sl,
        simulatePressure: sim,
        start: StrokeEndOptions.start(taperEnabled: true, customTaper: taper),
        end: StrokeEndOptions.end(taperEnabled: true, customTaper: taper),
        isComplete: !live,
      );
    }
    return StrokeOptions(
      size: s.size,
      thinning: th,
      smoothing: smoothing,
      streamline: sl,
      simulatePressure: sim,
      isComplete: !live,
    );
  }

  /// Cinta washi: banda recta del primer al último punto, translúcida, con
  /// rayitas y bordes rasgados.
  static void paintTape(Canvas canvas, Stroke s) {
    final a = Offset(s.points.first.x, s.points.first.y);
    final b = Offset(s.points.last.x, s.points.last.y);
    final len = (b - a).distance;
    if (len < 2) return;
    final h = s.size;
    canvas.save();
    canvas.translate(a.dx, a.dy);
    canvas.rotate(math.atan2(b.dy - a.dy, b.dx - a.dx));
    final path = Path()..moveTo(0, -h / 2);
    path.lineTo(len, -h / 2);
    // Borde rasgado derecho.
    var y = -h / 2;
    var out = true;
    while (y < h / 2) {
      y = math.min(y + h / 6, h / 2);
      path.lineTo(out ? len - h * 0.12 : len, y);
      out = !out;
    }
    path.lineTo(0, h / 2);
    y = h / 2;
    out = true;
    while (y > -h / 2) {
      y = math.max(y - h / 6, -h / 2);
      path.lineTo(out ? h * 0.12 : 0, y);
      out = !out;
    }
    path.close();
    final color = Color(s.color);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.72));
    canvas.save();
    canvas.clipPath(path);
    final stripe = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = h * 0.12;
    for (var x = -h; x < len + h; x += h * 0.55) {
      canvas.drawLine(Offset(x, h / 2), Offset(x + h * 0.6, -h / 2), stripe);
    }
    canvas.restore();
    canvas.restore();
  }
}
