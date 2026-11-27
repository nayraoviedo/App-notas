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

  test('listas: Enter continúa la lista y tocar la casilla la marca', () {
    final c = HighlightTextController(text: 'pan');
    c.selection = const TextSelection.collapsed(offset: 0);
    c.toggleList('check');
    expect(c.text, '☐ pan');
    // Enter al final.
    c.value = const TextEditingValue(text: '☐ pan\n', selection: TextSelection.collapsed(offset: 6));
    expect(c.text, '☐ pan\n☐ ');
    // Enter en una línea vacía termina la lista.
    c.value = TextEditingValue(text: '${c.text}\n', selection: TextSelection.collapsed(offset: c.text.length + 1));
    expect(c.text, '☐ pan\n');
    // Tocar la casilla.
    c.value = TextEditingValue(text: c.text, selection: const TextSelection.collapsed(offset: 0));
    expect(c.text.startsWith('☑ pan'), isTrue);
  });

  test('lista numerada sigue el número', () {
    final c = HighlightTextController(text: '1. uno');
    c.value = const TextEditingValue(text: '1. uno\n', selection: TextSelection.collapsed(offset: 7));
    expect(c.text, '1. uno\n2. ');
  });
}
