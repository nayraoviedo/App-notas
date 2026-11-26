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
}
