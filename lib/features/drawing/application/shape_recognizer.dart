import 'dart:math' as math;

import '../domain/drawing.dart';

enum RecognizedShape { line, circle, ellipse, rectangle, triangle, quad }

/// "Ajuste de figura": convierte un trazo a mano en una figura perfecta
/// (línea, círculo, elipse, rectángulo, triángulo o cuadrilátero).
/// Devuelve null si el trazo no se parece a ninguna.
class ShapeRecognizer {
  static (RecognizedShape, List<StrokePoint>)? recognize(List<StrokePoint> pts) {
    if (pts.length < 5) return null;
    final length = _pathLength(pts);
    if (length < 30) return null;

    final first = pts.first, last = pts.last;
    final chord = _dist(first.x, first.y, last.x, last.y);

    // Línea: casi recta de punta a punta.
    if (chord / length > 0.9) {
      var maxDev = 0.0;
      for (final p in pts) {
        maxDev = math.max(maxDev, _distToSegment(p, first, last));
      }
      if (maxDev < math.max(6, chord * 0.06)) {
        return (RecognizedShape.line, _densify([first, last]));
      }
      return null;
    }

    // Figuras cerradas: el final vuelve cerca del inicio.
    if (chord > length * 0.2) return null;

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    final w = maxX - minX, h = maxY - minY;
    if (w < 10 || h < 10) return null;
    final cx = minX + w / 2, cy = minY + h / 2, rx = w / 2, ry = h / 2;

    // Elipse / círculo: distancia normalizada al centro ≈ 1.
    var ellipseErr = 0.0;
    for (final p in pts) {
      final nx = (p.x - cx) / rx, ny = (p.y - cy) / ry;
      ellipseErr += (math.sqrt(nx * nx + ny * ny) - 1).abs();
    }
    ellipseErr /= pts.length;

    // Rectángulo alineado: puntos pegados a los bordes de la caja.
    var rectErr = 0.0;
    for (final p in pts) {
      final d = [p.x - minX, maxX - p.x, p.y - minY, maxY - p.y].reduce(math.min);
      rectErr += d / math.min(w, h);
    }
    rectErr /= pts.length;

    if (ellipseErr < 0.1 && ellipseErr < rectErr) {
      final ratio = w / h;
      if (ratio > 0.85 && ratio < 1.18) {
        final r = (rx + ry) / 2;
        return (RecognizedShape.circle, _ellipse(cx, cy, r, r));
      }
      return (RecognizedShape.ellipse, _ellipse(cx, cy, rx, ry));
    }
    if (rectErr < 0.06) {
      return (
        RecognizedShape.rectangle,
        _densify([
          StrokePoint(minX, minY),
          StrokePoint(maxX, minY),
          StrokePoint(maxX, maxY),
          StrokePoint(minX, maxY),
          StrokePoint(minX, minY),
        ]),
      );
    }

    // Triángulo o cuadrilátero inclinado: simplificar el contorno.
    final diag = math.sqrt(w * w + h * h);
    final closed = [...pts, pts.first];
    final simplified = _rdp(closed, diag * 0.09);
    final corners = simplified.length - 1; // el último repite el primero
    if (corners == 3 || corners == 4) {
      // Comprobar que el polígono explica bien el trazo.
      var err = 0.0;
      for (final p in pts) {
        var best = double.infinity;
        for (var i = 0; i + 1 < simplified.length; i++) {
          best = math.min(best, _distToSegment(p, simplified[i], simplified[i + 1]));
        }
        err += best;
      }
      err /= pts.length;
      if (err < diag * 0.035) {
        final poly = [...simplified.take(corners), simplified.first];
        return (
          corners == 3 ? RecognizedShape.triangle : RecognizedShape.quad,
          _densify(poly),
        );
      }
    }
    return null;
  }

  // ------------------------------------------------------------ Utilidades

  static double _dist(double ax, double ay, double bx, double by) =>
      math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));

  static double _pathLength(List<StrokePoint> pts) {
    var l = 0.0;
    for (var i = 1; i < pts.length; i++) {
      l += _dist(pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y);
    }
    return l;
  }

  static double _distToSegment(StrokePoint p, StrokePoint a, StrokePoint b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return _dist(p.x, p.y, a.x, a.y);
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
    return _dist(p.x, p.y, a.x + t * dx, a.y + t * dy);
  }

  /// Ramer–Douglas–Peucker.
  static List<StrokePoint> _rdp(List<StrokePoint> pts, double eps) {
    if (pts.length < 3) return pts;
    var maxD = 0.0;
    var idx = 0;
    for (var i = 1; i < pts.length - 1; i++) {
      final d = _distToSegment(pts[i], pts.first, pts.last);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD <= eps) return [pts.first, pts.last];
    final left = _rdp(pts.sublist(0, idx + 1), eps);
    final right = _rdp(pts.sublist(idx), eps);
    return [...left.take(left.length - 1), ...right];
  }

  static List<StrokePoint> _ellipse(double cx, double cy, double rx, double ry) => [
        for (var i = 0; i <= 72; i++)
          StrokePoint(
            cx + rx * math.cos(2 * math.pi * i / 72),
            cy + ry * math.sin(2 * math.pi * i / 72),
            0.5,
          ),
      ];

  /// Agrega puntos intermedios para que el trazo se dibuje parejo.
  static List<StrokePoint> _densify(List<StrokePoint> corners, {double step = 6}) {
    final out = <StrokePoint>[];
    for (var i = 0; i + 1 < corners.length; i++) {
      final a = corners[i], b = corners[i + 1];
      final n = math.max(1, (_dist(a.x, a.y, b.x, b.y) / step).ceil());
      for (var k = 0; k < n; k++) {
        final t = k / n;
        out.add(StrokePoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, 0.5));
      }
    }
    out.add(StrokePoint(corners.last.x, corners.last.y, 0.5));
    return out;
  }
}
