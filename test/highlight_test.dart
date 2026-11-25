import 'package:app_notas/features/notes/domain/note_block.dart';
import 'package:app_notas/features/notes/presentation/widgets/highlight_text_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resaltar la selección y que se mueva al escribir antes', () {
    final c = HighlightTextController(text: 'hola mundo');
    c.selection = const TextSelection(baseOffset: 5, extentOffset: 10);
    c.highlightSelection(0xFFFFF176);
    expect(c.marks.single.start, 5);
    expect(c.marks.single.end, 10);

    c.text = 'ya hola mundo'; // se escribió "ya " al inicio
    expect(c.marks.single.start, 8);
    expect(c.marks.single.end, 13);

    c.selection = const TextSelection(baseOffset: 8, extentOffset: 10);
    c.highlightSelection(null); // quitar parte del resaltado
    expect(c.marks.single.start, 10);
  });

  test('los resaltados se guardan y se leen', () {
    const marks = [TextMark(1, 4, 0xFF39FF14), TextMark(6, 9, 0xFFF8BBD0)];
    final back = TextMark.decode(TextMark.encode(marks));
    expect(back.length, 2);
    expect(back[1].color, 0xFFF8BBD0);
    expect(TextMark.decode('basura'), isEmpty);
  });
}
