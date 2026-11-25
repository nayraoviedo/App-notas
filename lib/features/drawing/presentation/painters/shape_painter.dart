import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/drawing.dart';

/// Dibuja una forma del panel "Forma" dentro de [size].
void paintShape(
  Canvas canvas,
  ShapeKind kind,
  Size size, {
  required Color color,
  required double strokeWidth,
  Color? fill,
}) {
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final w = size.width, h = size.height;
  final r = Offset.zero & size;
  final head = math.max(14.0, strokeWidth * 4);

  void outline(Path p) {
    if (fill != null) canvas.drawPath(p, Paint()..color = fill);
    canvas.drawPath(p, stroke);
  }

  void arrowHead(Offset tip, Offset from) {
    final dir = tip - from;
    if (dir.distance == 0) return;
    final a = math.atan2(dir.dy, dir.dx);
    final p = Path()
      ..moveTo(tip.dx + math.cos(a + 2.6) * head, tip.dy + math.sin(a + 2.6) * head)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(tip.dx + math.cos(a - 2.6) * head, tip.dy + math.sin(a - 2.6) * head);
    canvas.drawPath(p, stroke);
  }

  Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  Path regular(int n, {double rot = -math.pi / 2}) => poly([
        for (var i = 0; i < n; i++)
          Offset(w / 2 + math.cos(rot + i * 2 * math.pi / n) * w / 2,
              h / 2 + math.sin(rot + i * 2 * math.pi / n) * h / 2),
      ]);

  switch (kind) {
    case ShapeKind.line:
      canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), stroke);
    case ShapeKind.wavy:
      final p = Path()..moveTo(0, h / 2);
      for (var x = 0.0; x <= w; x += 2) {
        p.lineTo(x, h / 2 + math.sin(x / w * math.pi * 6) * h * 0.35);
      }
      canvas.drawPath(p, stroke);
    case ShapeKind.curve:
      canvas.drawPath(
          Path()
            ..moveTo(0, h * 0.1)
            ..quadraticBezierTo(w / 2, h * 1.7, w, h * 0.1),
          stroke);
    case ShapeKind.dashed:
      final dash = math.max(10.0, strokeWidth * 3);
      for (var x = 0.0; x < w; x += dash * 1.8) {
        canvas.drawLine(Offset(x, h / 2), Offset(math.min(x + dash, w), h / 2), stroke);
      }
    case ShapeKind.arrow:
      canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), stroke);
      arrowHead(Offset(w, h / 2), Offset(0, h / 2));
    case ShapeKind.doubleArrow:
      canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), stroke);
      arrowHead(Offset(w, h / 2), Offset(0, h / 2));
      arrowHead(Offset(0, h / 2), Offset(w, h / 2));
    case ShapeKind.curveArrow:
      final c = Offset(w / 2, h * 1.7);
      canvas.drawPath(
          Path()
            ..moveTo(0, h * 0.1)
            ..quadraticBezierTo(c.dx, c.dy, w, h * 0.1),
          stroke);
      arrowHead(Offset(w, h * 0.1), c);
    case ShapeKind.angle:
      canvas.drawPath(
          Path()
            ..moveTo(w, h)
            ..lineTo(0, h)
            ..lineTo(w * 0.75, 0),
          stroke);
      canvas.drawArc(Rect.fromCircle(center: Offset(0, h), radius: w * 0.22), -0.93, 0.93, false,
          stroke..strokeWidth = math.max(1, strokeWidth * 0.6));
    case ShapeKind.axes:
      canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), stroke);
      canvas.drawLine(Offset(w / 2, h), Offset(w / 2, 0), stroke);
      arrowHead(Offset(w, h / 2), Offset(0, h / 2));
      arrowHead(Offset(w / 2, 0), Offset(w / 2, h));
    case ShapeKind.axes3d:
      final o = Offset(w * 0.35, h * 0.62);
      for (final end in [Offset(o.dx, 0), Offset(w, o.dy), Offset(0, h)]) {
        canvas.drawLine(o, end, stroke);
        arrowHead(end, o);
      }
    case ShapeKind.brace:
      final p = Path()
        ..moveTo(w * 0.9, 0)
        ..quadraticBezierTo(w * 0.4, 0, w * 0.45, h * 0.2)
        ..lineTo(w * 0.45, h * 0.38)
        ..quadraticBezierTo(w * 0.45, h * 0.5, w * 0.05, h * 0.5)
        ..quadraticBezierTo(w * 0.45, h * 0.5, w * 0.45, h * 0.62)
        ..lineTo(w * 0.45, h * 0.8)
        ..quadraticBezierTo(w * 0.4, h, w * 0.9, h);
      canvas.drawPath(p, stroke);
    case ShapeKind.triangle:
      outline(poly([Offset(0, h), Offset(w, h * 0.8), Offset(w * 0.28, 0)]));
    case ShapeKind.isoTriangle:
      outline(poly([Offset(w / 2, 0), Offset(w, h), Offset(0, h)]));
    case ShapeKind.rightTriangle:
      outline(poly([Offset.zero, Offset(0, h), Offset(w, h)]));
    case ShapeKind.square:
    case ShapeKind.rectangle:
      outline(Path()..addRect(r));
    case ShapeKind.roundedRect:
      outline(Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(size.shortestSide * 0.18))));
    case ShapeKind.pill:
      outline(Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(h / 2))));
    case ShapeKind.trapezoid:
      outline(poly([Offset(w * 0.2, 0), Offset(w * 0.8, 0), Offset(w, h), Offset(0, h)]));
    case ShapeKind.parallelogram:
      outline(poly([Offset(w * 0.25, 0), Offset(w, 0), Offset(w * 0.75, h), Offset(0, h)]));
    case ShapeKind.circle:
    case ShapeKind.ellipse:
      outline(Path()..addOval(r));
    case ShapeKind.diamond:
      outline(poly([Offset(w / 2, 0), Offset(w, h / 2), Offset(w / 2, h), Offset(0, h / 2)]));
    case ShapeKind.pentagon:
      outline(regular(5));
    case ShapeKind.hexagon:
      outline(regular(6, rot: 0));
    case ShapeKind.star:
      final pts = <Offset>[];
      for (var i = 0; i < 10; i++) {
        final k = i.isEven ? 0.5 : 0.21;
        final a = -math.pi / 2 + i * math.pi / 5;
        pts.add(Offset(w / 2 + math.cos(a) * w * k, h * 0.55 + math.sin(a) * h * k * 1.08));
      }
      outline(poly(pts));
    case ShapeKind.heart:
      final p = Path()..moveTo(w / 2, h);
      p.cubicTo(-w * 0.05, h * 0.62, w * 0.02, -h * 0.02, w / 2, h * 0.25);
      p.cubicTo(w * 0.98, -h * 0.02, w * 1.05, h * 0.62, w / 2, h);
      outline(p..close());
    case ShapeKind.bubble:
      final body = RRect.fromLTRBR(0, 0, w, h * 0.78, Radius.circular(h * 0.18));
      final p = Path()..addRRect(body);
      final tail = Path()
        ..moveTo(w * 0.22, h * 0.7)
        ..lineTo(w * 0.15, h)
        ..lineTo(w * 0.42, h * 0.74)
        ..close();
      outline(Path.combine(PathOperation.union, p, tail));
    case ShapeKind.cloud:
      var p = Path()..addOval(Rect.fromLTWH(0, h * 0.35, w * 0.45, h * 0.55));
      for (final o in [
        Rect.fromLTWH(w * 0.18, h * 0.08, w * 0.42, h * 0.55),
        Rect.fromLTWH(w * 0.45, h * 0.15, w * 0.42, h * 0.5),
        Rect.fromLTWH(w * 0.55, h * 0.4, w * 0.45, h * 0.5),
        Rect.fromLTWH(w * 0.2, h * 0.45, w * 0.55, h * 0.55),
      ]) {
        p = Path.combine(PathOperation.union, p, Path()..addOval(o));
      }
      outline(p);
    case ShapeKind.cube:
      final d = math.min(w, h) * 0.28;
      final front = Rect.fromLTWH(0, d, w - d, h - d);
      final silhouette = poly([
        front.bottomLeft, front.topLeft, Offset(d, 0), Offset(w, 0), Offset(w, h - d), front.bottomRight,
      ]);
      outline(silhouette);
      canvas.drawRect(front, stroke);
      canvas.drawLine(front.topRight, Offset(w, 0), stroke);
    case ShapeKind.cylinder:
      final e = h * 0.18;
      final body = Path()
        ..moveTo(0, e / 2)
        ..lineTo(0, h - e / 2)
        ..arcTo(Rect.fromLTWH(0, h - e, w, e), math.pi, -math.pi, false)
        ..lineTo(w, e / 2)
        ..arcTo(Rect.fromLTWH(0, 0, w, e), 0, -math.pi, false)
        ..close();
      outline(body);
      canvas.drawOval(Rect.fromLTWH(0, 0, w, e), stroke);
    case ShapeKind.cone:
      final e = h * 0.18;
      final p = Path()
        ..moveTo(w / 2, 0)
        ..lineTo(w, h - e / 2)
        ..arcTo(Rect.fromLTWH(0, h - e, w, e), 0, math.pi, false)
        ..close();
      outline(p);
      canvas.drawArc(Rect.fromLTWH(0, h - e, w, e), math.pi, math.pi, false,
          Paint()
            ..color = color.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth * 0.7);
  }
}

class ShapePainter extends CustomPainter {
  const ShapePainter(this.kind, {required this.color, required this.strokeWidth, this.fill});
  final ShapeKind kind;
  final Color color;
  final double strokeWidth;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) =>
      paintShape(canvas, kind, size, color: color, strokeWidth: strokeWidth, fill: fill);

  @override
  bool shouldRepaint(ShapePainter old) =>
      old.kind != kind || old.color != color || old.strokeWidth != strokeWidth || old.fill != fill;
}
