import 'dart:typed_data';

import 'package:app_notas/features/export/docx_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Word: se arma un .docx y se vuelve a leer su texto', () {
    final w = DocxWriter()
      ..heading('Biología & química', level: 0)
      ..paragraph('Primera línea\nSegunda <línea>')
      ..bullet('Mitosis')
      ..labeled('01:20', 'Profase')
      ..image(Uint8List.fromList(List.filled(10, 1)), widthPx: 100, heightPx: 50);
    final bytes = w.build();
    expect(bytes.length, greaterThan(100));
    final text = readDocxText(bytes);
    expect(text, contains('Biología & química'));
    expect(text, contains('Segunda <línea>'));
    expect(text, contains('•  Mitosis'));
    expect(text, contains('01:20  Profase'));
  });
}
