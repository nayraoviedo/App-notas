import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

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

  test('EPUB y PowerPoint: se lee el texto en orden', () {
    List<int> zip(Map<String, String> files) {
      final a = Archive();
      for (final e in files.entries) {
        final b = utf8.encode(e.value);
        a.addFile(ArchiveFile(e.key, b.length, b));
      }
      return ZipEncoder().encode(a) as List<int>;
    }

    final epub = zip({
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="OEBPS/c.opf"/></rootfiles></container>',
      'OEBPS/c.opf': '<package><manifest><item id="a" href="uno.xhtml"/><item id="b" href="dos.xhtml"/></manifest>'
          '<spine><itemref idref="b"/><itemref idref="a"/></spine></package>',
      'OEBPS/uno.xhtml': '<html><body><h1>Inicio</h1><p>Hola &amp; adiós</p></body></html>',
      'OEBPS/dos.xhtml': '<html><body><h2>Prólogo</h2><p>Primero</p></body></html>',
    });
    final ch = readEpubChapters(epub);
    expect(ch.map((c) => c.$1), ['Prólogo', 'Inicio']);
    expect(ch.last.$2, contains('Hola & adiós'));

    final pptx = zip({
      'ppt/slides/slide10.xml': '<p:sld><a:p><a:r><a:t>Diez</a:t></a:r></a:p></p:sld>',
      'ppt/slides/slide2.xml': '<p:sld><a:p><a:r><a:t>Título</a:t></a:r></a:p><a:p><a:r><a:t>Punto</a:t></a:r></a:p></p:sld>',
    });
    expect(readPptxSlides(pptx), ['Título\nPunto', 'Diez']);
  });
}
