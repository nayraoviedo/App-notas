import 'dart:math' as math;
import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';

import '../../domain/drawing.dart';

/// Cómo se ve cada herramienta.
///
/// - Bolígrafo: línea firme, casi sin variación de grosor.
/// - Pluma estilográfica: tinta con trazo que engrosa con la presión.
/// - Lápiz: fino, algo transparente y con borde suave (grafito).
/// - Pincel: muy sensible a la presión, con puntas afinadas.
/// - Marcador: punta biselada (cambia de grosor según la dirección) y, si
///   se sube la sensibilidad, también con la presión o la velocidad.
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
      case ToolType.marker:
        // Punta biselada: el grosor cambia según la dirección del trazo
        // (fino en diagonal, ancho de lado), como un marcador de verdad.
        canvas.drawPath(_chisel(stroke, live), Paint()..color = color.withValues(alpha: color.a * 0.92));
      case ToolType.pen:
      case ToolType.fountain:
      case ToolType.brush:
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

  /// Marcador de punta biselada: la punta es una raya inclinada 45°; el
  /// trazo es todo lo que barre al moverse. Al ir en la dirección de la
  /// punta sale fino; de través, ancho.
  static Path _chisel(Stroke s, bool live) {
    if (!live && s.cachedPath != null) return s.cachedPath!;
    final pts = s.points;
    final th = (s.thinning ?? 0.3).clamp(0.0, 1.0);
    // Ancho de cada punto: con presión real o, si no hay, por la velocidad
    // (rápido = más fino), solo si la sensibilidad está encendida.
    final widths = <double>[];
    for (var i = 0; i < pts.length; i++) {
      var p = pts[i].p;
      if (p == null) {
        if (i == 0) {
          p = 0.8;
        } else {
          final d = (Offset(pts[i].x, pts[i].y) - Offset(pts[i - 1].x, pts[i - 1].y)).distance;
          p = (1 - (d / (s.size * 1.5)).clamp(0.0, 1.0) * 0.7);
        }
      }
      widths.add(s.size * (1 - th * (1 - p)));
    }
    // Suavizar los anchos para que no salten.
    for (var i = 1; i < widths.length; i++) {
      widths[i] = widths[i - 1] * 0.6 + widths[i] * 0.4;
    }
    const angle = -math.pi / 4;
    final dir = Offset(math.cos(angle), math.sin(angle));
    final nrm = Offset(-dir.dy, dir.dx);
    final path = Path();
    void addPoly(List<Offset> poly) {
      // Mismo sentido de giro en todas las piezas, para que se unan bien.
      var area = 0.0;
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i], b = poly[(i + 1) % poly.length];
        area += a.dx * b.dy - b.dx * a.dy;
      }
      path.addPolygon(area < 0 ? poly.reversed.toList() : poly, true);
    }

    List<Offset> nib(Offset c, double w) {
      final half = dir * (w / 2);
      final t = nrm * math.max(0.6, w * 0.12);
      return [c - half - t, c + half - t, c + half + t, c - half + t];
    }

    for (var i = 0; i < pts.length; i++) {
      final c = Offset(pts[i].x, pts[i].y);
      addPoly(nib(c, widths[i]));
      if (i == 0) continue;
      final b = Offset(pts[i - 1].x, pts[i - 1].y);
      final hb = dir * (widths[i - 1] / 2), hc = dir * (widths[i] / 2);
      addPoly([b - hb, b + hb, c + hc, c - hc]);
    }
    path.fillType = PathFillType.nonZero;
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
      ..color = const Color(0x59FFFFFF)
      ..strokeWidth = h * 0.12;
    for (var x = -h; x < len + h; x += h * 0.55) {
      canvas.drawLine(Offset(x, h / 2), Offset(x + h * 0.6, -h / 2), stripe);
    }
    canvas.restore();
    canvas.restore();
  }
}
