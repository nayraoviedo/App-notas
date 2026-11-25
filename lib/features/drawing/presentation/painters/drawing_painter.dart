import 'package:flutter/material.dart';

import '../../application/drawing_controller.dart';
import '../../domain/drawing.dart';
import 'stroke_renderer.dart';

/// Dibuja las capas en orden. Cada capa se pinta en su propio "saveLayer",
/// así el borrador y la opacidad solo afectan a esa capa.
void paintLayers(
  Canvas canvas,
  Size size,
  Drawing d, {
  int? activeIndex,
  Stroke? live,
}) {
  final bounds = Offset.zero & size;
  canvas.clipRect(bounds);
  for (var i = 0; i < d.layers.length; i++) {
    final layer = d.layers[i];
    if (!layer.visible) continue;
    final liveHere = i == activeIndex ? live : null;
    if (layer.strokes.isEmpty && liveHere == null) continue;

    canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, layer.opacity));
    for (final s in layer.strokes) {
      StrokeRenderer.paint(canvas, s);
    }
    if (liveHere != null) StrokeRenderer.paint(canvas, liveHere, live: true);
    canvas.restore();
  }
}

/// Lienzo en edición (se repinta con cada punto nuevo).
class DrawingPainter extends CustomPainter {
  DrawingPainter(this.controller) : super(repaint: controller);
  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) => paintLayers(
        canvas,
        size,
        controller.drawing,
        activeIndex: controller.activeLayerIndex,
        live: controller.currentStroke,
      );

  @override
  bool shouldRepaint(DrawingPainter old) => old.controller != controller;
}

/// Vista previa de solo lectura (miniatura en la nota).
class StaticDrawingPainter extends CustomPainter {
  const StaticDrawingPainter(this.drawing);
  final Drawing drawing;

  @override
  void paint(Canvas canvas, Size size) => paintLayers(canvas, size, drawing);

  @override
  bool shouldRepaint(StaticDrawingPainter old) => !identical(old.drawing, drawing);
}
