import 'package:app_notas/features/drawing/application/drawing_controller.dart';
import 'package:app_notas/features/drawing/domain/drawing.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el lazo elige trazos, textos y fotos y los mueve juntos', () {
    final c = DrawingController(Drawing.blank());
    c.startStroke(const Offset(100, 100), null);
    c.extendStroke(const Offset(150, 120), null);
    c.endStroke();
    c.addItem(const TextItem(id: 't1', x: 200, y: 200, text: 'Hola'));
    c.addItem(const ImageItem(id: 'i1', x: 250, y: 150, path: '/a.png', width: 80, height: 60));
    c.addItem(const TextItem(id: 'lejos', x: 800, y: 900, text: 'Fuera'));

    c.selectMode(InputMode.select);
    c.beginLasso(const Offset(50, 50));
    for (final p in const [Offset(400, 50), Offset(400, 400), Offset(50, 400)]) {
      c.extendLasso(p);
    }
    c.endLasso();
    expect(c.selectedStrokes, {0});
    expect(c.selectedItems, {'t1', 'i1'});
    expect(c.selectionBounds!.contains(const Offset(250, 150)), isTrue);

    c.beginItemChange();
    c.moveSelection(const Offset(10, 20));
    expect((c.findItem('t1')!.$2).x, 210);
    expect((c.findItem('i1')!.$2).y, 170);
    expect((c.findItem('lejos')!.$2).x, 800);

    c.duplicateSelection();
    expect(c.activeLayer.items.length, 5);
    c.deleteSelection();
    expect(c.activeLayer.items.length, 3);
  });
}
