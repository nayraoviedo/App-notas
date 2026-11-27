import 'package:app_notas/features/drawing/application/drawing_controller.dart';
import 'package:app_notas/features/drawing/application/page_move.dart';
import 'package:app_notas/features/drawing/domain/drawing.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void lassoAll(DrawingController c) {
  c.selectMode(InputMode.select);
  c.beginLasso(const Offset(0, 0));
  for (final p in const [Offset(1000, 0), Offset(1000, 1400), Offset(0, 1400)]) {
    c.extendLasso(p);
  }
  c.endLasso();
}

DrawingController withStroke() {
  final c = DrawingController(Drawing.blank());
  c.startStroke(const Offset(100, 100), null);
  c.extendStroke(const Offset(150, 120), null);
  c.endStroke();
  return c;
}

void main() {
  test('el lazo no toca una capa con candado ni una oculta', () {
    for (final change in [
      (DrawingLayer l) => l.copyWith(locked: true),
      (DrawingLayer l) => l.copyWith(visible: false),
    ]) {
      final c = withStroke();
      c.addItem(const TextItem(id: 't1', x: 200, y: 200, text: 'Hola'));
      c.updateLayer(0, change);
      lassoAll(c);
      expect(c.hasStrokeSelection, isFalse);
      c.deleteSelection();
      c.recolorSelection(0xFFFF0000);
      expect(c.activeLayer.strokes.length, 1);
      expect(c.activeLayer.items.length, 1);
      final (s, i) = c.takeSelection();
      expect(s, isEmpty);
      expect(i, isEmpty);
    }
  });

  test('pasar a otra hoja: deshacer lo devuelve a donde estaba antes de arrastrar', () {
    final from = withStroke();
    final original = from.activeLayer.strokes.first.points.first.y;
    lassoAll(from);
    from.beginItemChange(); // empieza el arrastre
    from.moveSelection(const Offset(0, 1500)); // más allá del borde de abajo
    final (strokes, _) = from.takeSelection(afterDrag: true);
    expect(strokes, hasLength(1));
    expect(from.activeLayer.strokes, isEmpty);

    // La otra hoja recibe el trazo.
    final to = DrawingController(Drawing.blank());
    final before = to.drawing;
    to.addContent(strokes, const []);
    final after = to.drawing;
    expect(to.activeLayer.strokes, hasLength(1));

    // Deshacer en la hoja que recibió: vuelve a como estaba.
    to.undo();
    expect(identical(to.drawing, before), isTrue);
    // Y la hoja de origen (cerrada) se deshace con su historial guardado,
    // en un solo paso, al lugar de antes del arrastre.
    final step = undoClosedPage(from.history)!;
    expect(step.$1.layers.first.strokes, hasLength(1));
    expect(step.$1.layers.first.strokes.first.points.first.y, original);

    // Rehacer en las dos vuelve a dejarlo pasado.
    to.redo();
    expect(identical(to.drawing, after), isTrue);
    final again = redoClosedPage(step.$2)!;
    expect(again.$1.layers.first.strokes, isEmpty);
    expect(undoClosedPage((const [], const [], Drawing.blank())), isNull);
  });
}
