import 'package:flutter/material.dart';

import '../../application/drawing_controller.dart';
import '../../domain/drawing.dart';
import 'stroke_renderer.dart';

/// Pinta los trazos de UNA capa dentro de su propio "saveLayer", así el
/// borrador y la opacidad solo afectan a esa capa.
void paintLayer(Canvas canvas, Size size, DrawingLayer layer, {Stroke? live, bool clip = true}) {
  if (!layer.visible) return;
  if (layer.strokes.isEmpty && live == null) return;
  // Sin recorte, la capa abarca también lo que se sale de la hoja.
  final bounds = clip ? Offset.zero & size : (Offset.zero & size).inflate(size.longestSide);
  canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, layer.opacity));
  for (final s in layer.strokes) {
    StrokeRenderer.paint(canvas, s);
  }
  if (live != null) StrokeRenderer.paint(canvas, live, live: true);
  canvas.restore();
}

/// Pinta todas las capas en orden (para exportar). [paintItems] dibuja los
/// textos y fotos de cada capa encima de sus trazos.
void paintLayers(
  Canvas canvas,
  Size size,
  Drawing d, {
  int? activeIndex,
  Stroke? live,
  void Function(Canvas canvas, DrawingLayer layer)? paintItems,
}) {
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  for (var i = 0; i < d.layers.length; i++) {
    final layer = d.layers[i];
    // Primero fotos y textos; los trazos encima.
    if (paintItems != null && layer.visible && layer.items.isNotEmpty) {
      paintItems(canvas, layer);
    }
    paintLayer(canvas, size, layer, live: i == activeIndex ? live : null);
  }
  canvas.restore();
}

/// Trazos de una capa en edición (se repinta con cada punto nuevo).
class LayerPainter extends CustomPainter {
  LayerPainter(this.controller, this.index, {this.clip = true}) : super(repaint: controller);
  final DrawingController controller;
  final int index;

  /// false mientras se arrastra algo con el lazo hacia otra hoja (para que
  /// se vea fuera del borde).
  final bool clip;

  @override
  void paint(Canvas canvas, Size size) {
    final layers = controller.drawing.layers;
    if (index >= layers.length) return;
    if (clip) canvas.clipRect(Offset.zero & size);
    paintLayer(
      canvas,
      size,
      layers[index],
      live: index == controller.activeLayerIndex ? controller.currentStroke : null,
      clip: clip,
    );
    // Círculo del borrador por área, para ver qué se va a borrar.
    final at = controller.eraserAt;
    if (at != null && index == controller.activeLayerIndex) {
      final r = controller.eraserRadius;
      canvas.drawCircle(at, r, Paint()..color = const Color(0x22000000));
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..color = const Color(0x88000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(LayerPainter old) =>
      old.controller != controller || old.index != index || old.clip != clip;
}

/// Trazos de una capa, solo lectura (miniaturas).
class StaticLayerPainter extends CustomPainter {
  const StaticLayerPainter(this.layer);
  final DrawingLayer layer;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    paintLayer(canvas, size, layer);
  }

  @override
  bool shouldRepaint(StaticLayerPainter old) => !identical(old.layer, layer);
}
