import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Escritor mínimo de documentos Word (.docx): títulos, párrafos, viñetas e
/// imágenes PNG/JPG. Un .docx es un zip con XML adentro.
class DocxWriter {
  final _body = StringBuffer();
  final _media = <String, Uint8List>{};
  int _img = 0;

  static String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

  void _run(String text, {bool bold = false, bool italic = false, int? halfPoints, String? color}) {
    final lines = text.split('\n');
    _body.write('<w:r><w:rPr>');
    if (bold) _body.write('<w:b/>');
    if (italic) _body.write('<w:i/>');
    if (color != null) _body.write('<w:color w:val="$color"/>');
    if (halfPoints != null) _body.write('<w:sz w:val="$halfPoints"/><w:szCs w:val="$halfPoints"/>');
    _body.write('</w:rPr>');
    for (final (i, l) in lines.indexed) {
      if (i > 0) _body.write('<w:br/>');
      _body.write('<w:t xml:space="preserve">${_esc(l)}</w:t>');
    }
    _body.write('</w:r>');
  }

  /// Título (nivel 0 = título del documento, 1 = sección, 2 = subsección).
  void heading(String text, {int level = 1}) {
    final size = switch (level) { 0 => 40, 1 => 32, _ => 26 };
    _body.write('<w:p><w:pPr><w:spacing w:before="240" w:after="120"/></w:pPr>');
    _run(text, bold: true, halfPoints: size, color: level == 0 ? '8A3B22' : '3B2A22');
    _body.write('</w:p>');
  }

  void paragraph(String text, {bool italic = false, int halfPoints = 22, String? color}) {
    _body.write('<w:p><w:pPr><w:spacing w:after="120"/></w:pPr>');
    _run(text, italic: italic, halfPoints: halfPoints, color: color);
    _body.write('</w:p>');
  }

  /// Párrafo con una parte en negrita al inicio ("12:30  Tema").
  void labeled(String label, String text) {
    _body.write('<w:p><w:pPr><w:spacing w:after="100"/></w:pPr>');
    _run('$label  ', bold: true, halfPoints: 22, color: '1677FF');
    _run(text, halfPoints: 22);
    _body.write('</w:p>');
  }

  void bullet(String text) {
    _body.write('<w:p><w:pPr><w:ind w:left="360" w:hanging="240"/><w:spacing w:after="60"/></w:pPr>');
    _run('•  $text', halfPoints: 22);
    _body.write('</w:p>');
  }

  void pageBreak() => _body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');

  /// Imagen a lo ancho de la página (máx. 16 cm), manteniendo proporción.
  void image(Uint8List bytes, {required int widthPx, required int heightPx, bool jpg = false}) {
    if (widthPx <= 0 || heightPx <= 0) return;
    _img++;
    final name = 'image$_img.${jpg ? 'jpeg' : 'png'}';
    _media[name] = bytes;
    const maxW = 5760000; // 16 cm en EMU
    const maxH = 8640000; // 24 cm
    var cx = maxW, cy = (maxW * heightPx / widthPx).round();
    if (cy > maxH) {
      cy = maxH;
      cx = (maxH * widthPx / heightPx).round();
    }
    _body.write('<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$_img" name="Imagen $_img"/>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="$_img" name="$name"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="rImg$_img"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>');
  }

  Uint8List build() {
    final rels = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    var i = 0;
    for (final name in _media.keys) {
      i++;
      rels.write('<Relationship Id="rImg$i" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="media/$name"/>');
    }
    rels.write('</Relationships>');

    final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
        '<w:body>$_body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>';

    const types = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Default Extension="jpeg" ContentType="image/jpeg"/>'
        '<Override PartName="/word/document.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>';
    const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="word/document.xml"/></Relationships>';

    final a = Archive();
    void add(String name, List<int> bytes) => a.addFile(ArchiveFile(name, bytes.length, bytes));
    add('[Content_Types].xml', utf8.encode(types));
    add('_rels/.rels', utf8.encode(rootRels));
    add('word/document.xml', utf8.encode(doc));
    add('word/_rels/document.xml.rels', utf8.encode(rels.toString()));
    for (final e in _media.entries) {
      add('word/media/${e.key}', e.value);
    }
    final out = ZipEncoder().encode(a) as List<int>;
    return Uint8List.fromList(out);
  }
}

/// Lee el texto de un .docx (para importarlo como nota): un párrafo por línea.
String readDocxText(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final doc = zip.files.where((f) => f.name == 'word/document.xml').firstOrNull;
  if (doc == null) throw const FormatException('Ese archivo no parece un documento de Word (.docx).');
  final xml = utf8.decode(doc.content as List<int>, allowMalformed: true);
  final out = StringBuffer();
  for (final p in RegExp(r'<w:p[ >][\s\S]*?</w:p>|<w:p/>').allMatches(xml)) {
    final para = p.group(0)!;
    final buf = StringBuffer();
    for (final m in RegExp(r'<w:t(?: [^>]*)?>([\s\S]*?)</w:t>|<w:tab/>|<w:br/>').allMatches(para)) {
      final g = m.group(0)!;
      if (g == '<w:tab/>') {
        buf.write('\t');
      } else if (g == '<w:br/>') {
        buf.write('\n');
      } else {
        buf.write(m.group(1));
      }
    }
    out.writeln(_unescape(buf.toString()));
  }
  return out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

// --------------------------------------------------------------- EPUB

/// Capítulos de un libro EPUB: (título, texto). En el orden del libro.
List<(String, String)> readEpubChapters(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? read(String name) {
    final f = zip.files.where((f) => f.name == name).firstOrNull;
    return f == null ? null : utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final container = read('META-INF/container.xml');
  final opfPath = container == null ? null : RegExp(r'full-path="([^"]+)"').firstMatch(container)?.group(1);
  final opf = opfPath == null ? null : read(opfPath);
  if (opf == null) throw const FormatException('Ese archivo no parece un libro EPUB.');
  final base = opfPath!.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1) : '';
  final hrefs = {
    for (final m in RegExp(r'<item\b[^>]*>').allMatches(opf))
      if (RegExp(r'id="([^"]+)"').firstMatch(m.group(0)!)?.group(1) case final id?)
        id: RegExp(r'href="([^"]+)"').firstMatch(m.group(0)!)?.group(1) ?? '',
  };
  final order = [for (final m in RegExp(r'<itemref\b[^>]*idref="([^"]+)"').allMatches(opf)) m.group(1)!];
  final out = <(String, String)>[];
  for (final id in order) {
    final href = hrefs[id];
    if (href == null || href.isEmpty) continue;
    final html = read(base + Uri.decodeFull(href));
    if (html == null) continue;
    final title = RegExp(r'<h[1-3][^>]*>([\s\S]*?)</h[1-3]>').firstMatch(html)?.group(1);
    final text = htmlToText(html);
    if (text.trim().length < 3) continue;
    out.add((title == null ? 'Capítulo ${out.length + 1}' : htmlToText(title), text));
  }
  return out;
}

/// Texto simple a partir de HTML/XHTML (párrafos separados por línea).
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<(script|style|head)[\s\S]*?</\1>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|h[1-6]|li|tr|section)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = _unescape(s.replaceAll('&nbsp;', ' ').replaceAll('&#160;', ' '));
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r' *\n *'), '\n');
  return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

// ---------------------------------------------------------- PowerPoint

/// Texto de cada diapositiva de un .pptx, en orden.
List<String> readPptxSlides(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final slides = zip.files.where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name)).toList()
    ..sort((a, b) => int.parse(RegExp(r'\d+').firstMatch(a.name.split('/').last)!.group(0)!)
        .compareTo(int.parse(RegExp(r'\d+').firstMatch(b.name.split('/').last)!.group(0)!)));
  if (slides.isEmpty) throw const FormatException('Ese archivo no parece una presentación de PowerPoint (.pptx).');
  return [
    for (final f in slides)
      () {
        final xml = utf8.decode(f.content as List<int>, allowMalformed: true);
        final paras = <String>[];
        for (final p in RegExp(r'<a:p>[\s\S]*?</a:p>|<a:p [\s\S]*?</a:p>').allMatches(xml)) {
          final t = [for (final m in RegExp(r'<a:t>([\s\S]*?)</a:t>').allMatches(p.group(0)!)) m.group(1)].join();
          if (t.trim().isNotEmpty) paras.add(_unescape(t));
        }
        return paras.join('\n');
      }(),
  ];
}
