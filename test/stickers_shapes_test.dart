import 'package:app_notas/features/drawing/domain/drawing.dart';
import 'package:app_notas/features/drawing/presentation/painters/sticker_painter.dart';
import 'package:app_notas/features/notes/data/notes_repository.dart';
import 'package:app_notas/features/notes/presentation/create_note_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stickers, formas e interlineado se guardan y se leen igual', () {
    final layer = DrawingLayer(id: 'l', name: 'Capa', items: const [
      StickerItem(id: 'a', x: 1, y: 2, scale: 1.5, sticker: 'memo_heart', width: 220, height: 200),
      ShapeItem(id: 'b', x: 3, y: 4, shape: ShapeKind.star, color: 0xFF112233, strokeWidth: 6, fill: 0x59112233),
      TextItem(id: 'c', x: 5, y: 6, text: 'Hola', lineHeight: 1.5),
    ]);
    final back = DrawingLayer.fromJson(layer.toJson());
    final st = back.items[0] as StickerItem;
    expect(st.sticker, 'memo_heart');
    expect(st.scale, 1.5);
    final sh = back.items[1] as ShapeItem;
    expect(sh.shape, ShapeKind.star);
    expect(sh.fill, 0x59112233);
    expect(sh.strokeWidth, 6);
    expect((back.items[2] as TextItem).lineHeight, 1.5);
  });

  test('un trazo con pluma estilográfica guarda presión y estabilización', () {
    final s = Stroke(
      tool: ToolType.fountain,
      color: 1,
      size: 4,
      thinning: 0.7,
      streamline: 0.3,
      points: const [StrokePoint(0, 0)],
    );
    final back = Stroke.fromJson(s.toJson());
    expect(back.tool, ToolType.fountain);
    expect(back.thinning, closeTo(0.7, 0.01));
    expect(back.streamline, closeTo(0.3, 0.01));
  });

  test('plantilla o herramienta desconocida no rompe la carga', () {
    final p = PaperStyle.fromJson({'template': 'noExiste'});
    expect(p.template, PaperTemplate.lined);
    final s = Stroke.fromJson({'t': 'laser', 'c': 1, 's': 2, 'pts': [0, 0, -1]});
    expect(s.tool, ToolType.pen);
  });

  test('todos los stickers tienen id único', () {
    final ids = stickerCatalog.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(stickerById('cactus'), isNotNull);
  });

  test('crear nota con tapa pone la tapa primero', () {
    const opts = NewNoteOptions(
      title: 'Biología',
      withSheet: true,
      paper: PaperStyle(template: PaperTemplate.cornell),
      landscape: false,
    );
    final pages = opts.pages();
    expect(pages, hasLength(2));
    expect(pages.first.paper.template, PaperTemplate.cover);
    expect((pages.first.layers.single.items.single as TextItem).text, 'Biología');
    expect(pages.last.paper.template, PaperTemplate.cornell);
  });

  test('etiquetas', () {
    expect(NotesRepository.decodeTags('clase| ideas ||viaje'), ['clase', 'ideas', 'viaje']);
    expect(NotesRepository.decodeTags(''), isEmpty);
  });
}
