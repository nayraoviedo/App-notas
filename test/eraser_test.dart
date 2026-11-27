import 'package:app_notas/features/drawing/application/drawing_controller.dart';
import 'package:app_notas/features/drawing/domain/drawing.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el borrador por área corta solo lo que toca', () {
    final c = DrawingController(Drawing.blank());
    // Una línea recta de 0 a 300 (solo dos puntos) y otra lejos.
    c.startStroke(const Offset(0, 100), null);
    c.extendStroke(const Offset(300, 100), null);
    c.endStroke();
    c.startStroke(const Offset(0, 400), null);
    c.extendStroke(const Offset(300, 400), null);
    c.endStroke();
    expect(c.activeLayer.strokes.length, 2);

    c.selectTool(ToolType.eraser);
    c.setSize(20);
    c.startStroke(const Offset(150, 60), null);
    c.extendStroke(const Offset(150, 140), null);
    c.endStroke();

    final strokes = c.activeLayer.strokes;
    // La primera línea quedó en dos pedazos y la de abajo intacta.
    expect(strokes.length, 3);
    expect(strokes.where((s) => s.points.first.y == 400).length, 1);
    final top = strokes.where((s) => s.points.first.y == 100).toList();
    expect(top.length, 2);
    expect(top.every((s) => s.points.every((p) => (p.x - 150).abs() > 10)), isTrue);
    // No se guarda ningún trazo "borrador".
    expect(strokes.any((s) => s.tool == ToolType.eraser), isFalse);

    // Un solo deshacer lo devuelve todo.
    c.undo();
    expect(c.activeLayer.strokes.length, 2);
  });

  test('el borrador borra en otras capas, pero no en las bloqueadas', () {
    final c = DrawingController(Drawing.blank());
    c.startStroke(const Offset(0, 100), null);
    c.extendStroke(const Offset(300, 100), null);
    c.endStroke();
    c.addLayer(); // ahora la activa es la capa 2, vacía
    expect(c.activeLayerIndex, 1);

    c.selectTool(ToolType.eraser);
    c.setSize(20);
    c.startStroke(const Offset(150, 60), null);
    c.extendStroke(const Offset(150, 140), null);
    c.endStroke();
    expect(c.drawing.layers[0].strokes.length, 2, reason: 'se cortó la línea de la capa 1');

    c.undo();
    c.updateLayer(0, (l) => l.copyWith(locked: true));
    c.startStroke(const Offset(150, 60), null);
    c.extendStroke(const Offset(150, 140), null);
    c.endStroke();
    expect(c.drawing.layers[0].strokes.length, 1, reason: 'con candado no se borra');

    // Borrar trazos enteros también llega a otras capas.
    c.updateLayer(0, (l) => l.copyWith(locked: false));
    c.selectMode(InputMode.eraseStrokes);
    c.beginEraseStrokes();
    c.eraseStrokesAt(const Offset(10, 100));
    expect(c.drawing.layers[0].strokes, isEmpty);
  });

  test('el lienzo infinito crece al dibujar cerca del borde', () {
    final c = DrawingController(Drawing.blank())..setInfinite(true);
    expect(c.drawing.infinite, isTrue);
    expect(c.drawing.width, Drawing.infiniteStart);
    c.startStroke(const Offset(2900, 2900), null);
    c.extendStroke(const Offset(2950, 2950), null);
    c.endStroke();
    expect(c.drawing.width, greaterThan(4000));
    expect(c.drawing.height, greaterThan(4000));
    final again = Drawing.fromJson(c.drawing.toJson());
    expect(again.infinite, isTrue);
  });

  test('el lienzo infinito vertical solo crece hacia abajo', () {
    final c = DrawingController(Drawing.blank())..setInfinite(true, grow: InfiniteGrow.down);
    expect(c.drawing.width, Drawing.a4Width);
    c.startStroke(const Offset(950, 2900), null);
    c.extendStroke(const Offset(990, 2950), null);
    c.endStroke();
    expect(c.drawing.width, Drawing.a4Width);
    expect(c.drawing.height, greaterThan(4000));
    expect(Drawing.fromJson(c.drawing.toJson()).grow, InfiniteGrow.down);
  });
}
