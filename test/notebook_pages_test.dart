import 'dart:ui' as ui;

import 'package:app_notas/features/drawing/application/drawing_controller.dart';
import 'package:app_notas/features/drawing/domain/drawing.dart';
import 'package:app_notas/features/drawing/presentation/painters/stroke_renderer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la tapa no acepta trazos, borrador, textos, fotos ni lazo', () {
    final c = DrawingController(
        Drawing.blank(paper: const PaperStyle(template: PaperTemplate.cover)));
    expect(c.readOnly, isTrue);
    c.startStroke(const Offset(100, 100), null);
    c.extendStroke(const Offset(200, 200), null);
    c.endStroke();
    c.addItem(const TextItem(id: 't', x: 100, y: 100, text: 'Hola'));
    c.addItem(const ImageItem(id: 'i', x: 100, y: 100, path: '/a.png', width: 50, height: 50));
    c.selectMode(InputMode.select);
    c.beginLasso(const Offset(0, 0));
    expect(c.drawing.layers.first.strokes, isEmpty);
    expect(c.drawing.layers.first.items, isEmpty);
    expect(c.lasso, isNull);
    expect(c.canUndo, isFalse);
  });

  test('lo elegido con el lazo se puede llevar a otra hoja', () {
    final a = DrawingController(Drawing.blank());
    a.addItem(const ImageItem(id: 'foto', x: 300, y: 300, path: '/a.png', width: 80, height: 60));
    a.startStroke(const Offset(280, 280), null);
    a.extendStroke(const Offset(320, 320), null);
    a.endStroke();
    a.selectMode(InputMode.select);
    a.beginLasso(const Offset(200, 200));
    for (final p in const [Offset(400, 200), Offset(400, 400), Offset(200, 400)]) {
      a.extendLasso(p);
    }
    a.endLasso();
    final (strokes, items) = a.takeSelection();
    expect(strokes.length, 1);
    expect(items.single.id, 'foto');
    expect(a.activeLayer.items, isEmpty);
    expect(a.activeLayer.strokes, isEmpty);

    final b = DrawingController(Drawing.blank());
    b.addContent([for (final s in strokes) DrawingController.shiftedStroke(s, const Offset(0, -100))],
        [for (final it in items) it.moved(y: it.y - 100)]);
    expect(b.activeLayer.items.single.y, 200);
    expect(b.activeLayer.strokes.single.points.first.y, 180);
    expect(b.selectedItems, {'foto'});
    expect(b.selectedStrokes, {0});
    // Y se puede deshacer en cada hoja por separado.
    b.undo();
    expect(b.activeLayer.items, isEmpty);
    a.undo();
    expect(a.activeLayer.items.single.id, 'foto');
  });

  test('un elemento arrastrado solo queda elegido para pasar de hoja', () {
    final c = DrawingController(Drawing.blank());
    c.addItem(const TextItem(id: 't', x: 100, y: 100, text: 'Hola'));
    c.selectForMove('t');
    expect(c.selectedItems, {'t'});
    expect(c.selectedItemId, isNull);
    expect(c.selectionBounds, isNotNull);
  });

  test('el marcador cambia de grosor según la dirección', () {
    Stroke line(Offset a, Offset b) => Stroke(
          tool: ToolType.marker,
          color: 0xFF000000,
          size: 20,
          thinning: 0,
          points: [
            for (var i = 0; i <= 20; i++)
              StrokePoint(a.dx + (b.dx - a.dx) * i / 20, a.dy + (b.dy - a.dy) * i / 20),
          ],
        );
    // La punta está inclinada 45°: a lo largo de ella sale fino; de través, ancho.
    final along = line(const Offset(0, 100), const Offset(100, 0));
    final across = line(const Offset(0, 0), const Offset(100, 100));
    Path outline(Stroke s) {
      final rec = ui.PictureRecorder();
      StrokeRenderer.paint(Canvas(rec), s);
      rec.endRecording().dispose();
      return s.cachedPath!;
    }

    // 6 px a un lado de la mitad de cada línea.
    expect(outline(across).contains(const Offset(54.2, 45.8)), isTrue);
    expect(outline(along).contains(const Offset(54.2, 54.2)), isFalse);
  });
}
