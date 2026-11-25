import 'dart:ui';

import 'package:app_notas/features/drawing/application/drawing_controller.dart';
import 'package:app_notas/features/drawing/domain/drawing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la hoja se guarda y se lee igual (JSON)', () {
    final d = Drawing.blank(
      paper: const PaperStyle(template: PaperTemplate.grid, spacing: 32, imagePath: '/x.jpg'),
    ).copyWith(layers: [
      DrawingLayer(id: 'a', name: 'Fondo', opacity: 0.5, strokes: [
        Stroke(tool: ToolType.brush, color: 0xFF112233, size: 8, points: const [
          StrokePoint(1, 2, 0.5),
          StrokePoint(3, 4),
        ]),
      ]),
    ]);
    final back = Drawing.fromJson(d.toJson());
    expect(back.paper.template, PaperTemplate.grid);
    expect(back.paper.imagePath, '/x.jpg');
    expect(back.layers.single.opacity, 0.5);
    final s = back.layers.single.strokes.single;
    expect(s.tool, ToolType.brush);
    expect(s.points[0].p, 0.5);
    expect(s.points[1].p, isNull);
  });

  test('trazos van a la capa activa y se pueden deshacer/rehacer', () {
    final c = DrawingController(Drawing.blank());
    c.addLayer(); // capa 2 queda activa, encima
    c.startStroke(const Offset(10, 10), null);
    c.extendStroke(const Offset(50, 50), null);
    c.endStroke();
    expect(c.drawing.layers[1].strokes, hasLength(1));
    expect(c.drawing.layers[0].strokes, isEmpty);

    c.undo();
    expect(c.drawing.layers[1].strokes, isEmpty);
    c.redo();
    expect(c.drawing.layers[1].strokes, hasLength(1));
  });

  test('no se dibuja en una capa bloqueada', () {
    final c = DrawingController(Drawing.blank());
    c.updateLayer(0, (l) => l.copyWith(locked: true));
    c.startStroke(const Offset(1, 1), null);
    c.endStroke();
    expect(c.drawing.layers[0].strokes, isEmpty);
  });

  test('borrar trazos completos', () {
    final c = DrawingController(Drawing.blank());
    c.startStroke(const Offset(0, 0), null);
    c.extendStroke(const Offset(100, 0), null);
    c.endStroke();
    c.beginEraseStrokes();
    c.eraseStrokesAt(const Offset(50, 3));
    expect(c.activeLayer.strokes, isEmpty);
  });

  test('reordenar capas mantiene la activa', () {
    final c = DrawingController(Drawing.blank())..addLayer();
    final activeId = c.activeLayer.id;
    c.reorderLayers(c.drawing.layers.reversed.map((l) => l.id).toList());
    expect(c.activeLayer.id, activeId);
    expect(c.activeLayerIndex, 0);
  });
}
