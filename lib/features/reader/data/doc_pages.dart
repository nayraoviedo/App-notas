import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart' show Printing;

import '../../../core/platform_info.dart';
import 'doc_source.dart' show imageExtensions;

/// Una página del documento ya dibujada como imagen.
class DocPage {
  const DocPage(this.path, this.width, this.height);
  final String path;
  final double width;
  final double height;
  double get ratio => height / width;
}

/// Convierte un PDF en imágenes (una por página) y las guarda en la caché,
/// para que la segunda vez abra al instante. Las páginas llegan de a una.
Stream<DocPage> docPages(String docPath) async* {
  final ext = p.extension(docPath).toLowerCase();
  if (imageExtensions.contains(ext)) {
    final size = await _imageSize(docPath);
    yield DocPage(docPath, size.width, size.height);
    return;
  }
  final cache = Directory(p.join((await getApplicationCacheDirectory()).path, 'kumo_doc_pages',
      p.basenameWithoutExtension(docPath)));
  final index = File(p.join(cache.path, 'pages.json'));
  if (await index.exists()) {
    try {
      final list = jsonDecode(await index.readAsString()) as List;
      final pages = [
        for (final m in list.cast<Map>())
          DocPage(p.join(cache.path, m['f'] as String), (m['w'] as num).toDouble(), (m['h'] as num).toDouble()),
      ];
      if (pages.every((pg) => File(pg.path).existsSync())) {
        for (final pg in pages) {
          yield pg;
        }
        return;
      }
    } catch (_) {}
  }
  if (await cache.exists()) await cache.delete(recursive: true);
  await cache.create(recursive: true);

  final done = <Map<String, Object>>[];
  Future<DocPage> save(List<int> bytes, String extension, double w, double h) async {
    final f = '${done.length + 1}$extension';
    await File(p.join(cache.path, f)).writeAsBytes(bytes, flush: true);
    done.add({'f': f, 'w': w, 'h': h});
    return DocPage(p.join(cache.path, f), w, h);
  }

  if (isPhone) {
    final doc = await PdfDocument.openFile(docPath);
    try {
      for (var i = 1; i <= doc.pagesCount; i++) {
        // En Android hay que cerrar cada página antes de abrir la siguiente.
        final page = await doc.getPage(i);
        try {
          final scale = 1400 / page.width;
          final img = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.jpeg,
            quality: 88,
            backgroundColor: '#ffffff',
          );
          if (img == null) continue;
          yield await save(img.bytes, '.jpg', page.width, page.height);
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
  } else {
    // En la compu (pdfx no va en Linux) se usa el lector de "printing".
    final info = await Printing.info();
    if (!info.canRaster) throw Exception('No se puede leer el PDF en esta compu.');
    final bytes = await File(docPath).readAsBytes();
    await for (final page in Printing.raster(bytes, dpi: 130)) {
      yield await save(await page.toPng(), '.png', page.width.toDouble(), page.height.toDouble());
    }
  }
  await index.writeAsString(jsonEncode(done), flush: true);
}

Future<ui.Size> _imageSize(String path) async {
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final size = ui.Size(desc.width.toDouble(), desc.height.toDouble());
  desc.dispose();
  buffer.dispose();
  return size;
}
