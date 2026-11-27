import 'dart:io';

import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';

import '../../core/files/file_storage.dart';
import '../drawing/data/drawing_store.dart';
import '../drawing/domain/drawing.dart';
import '../notes/data/notes_repository.dart';
import 'package:printing/printing.dart' show Printing;
import '../../core/platform_info.dart';

typedef ImportProgress = void Function(int done, int total);

/// Importa PDFs y fotos como hojas: cada página/foto se vuelve el fondo de
/// una hoja donde se puede escribir y dibujar encima, con capas.
class ImportService {
  ImportService(this._storage, this._drawings, this._notes);

  final FileStorage _storage;
  final DrawingStore _drawings;
  final NotesRepository _notes;

  /// Ancho en píxeles al que se renderiza cada página (nítido sin pesar mucho).
  static const renderWidth = 1600.0;

  Future<String?> pickPdf() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    return r?.files.single.path;
  }

  /// Crea una nota nueva con todas las páginas del PDF.
  Future<String> importPdfAsNewNote(
    String pdfPath, {
    String? notebookId,
    ImportProgress? onProgress,
  }) async {
    final title = p.basenameWithoutExtension(pdfPath);
    final noteId = await _notes.createNote(title: title, notebookId: notebookId);
    await importPdf(noteId, pdfPath, onProgress: onProgress);
    return noteId;
  }

  /// Agrega cada página del PDF como una hoja al final de la nota.
  Future<int> importPdf(String noteId, String pdfPath, {ImportProgress? onProgress}) async {
    if (!isPhone) return _importPdfDesktop(noteId, pdfPath, onProgress: onProgress);
    final doc = await PdfDocument.openFile(pdfPath);
    var count = 0;
    try {
      final total = doc.pagesCount;
      for (var i = 1; i <= total; i++) {
        onProgress?.call(i - 1, total);
        // En Android hay que cerrar cada página antes de abrir la siguiente.
        final page = await doc.getPage(i);
        try {
          final w = page.width;
          final h = page.height;
          final scale = renderWidth / w;
          final image = await page.render(
            width: w * scale,
            height: h * scale,
            format: PdfPageImageFormat.jpeg,
            quality: 90,
            backgroundColor: '#ffffff',
          );
          final bytes = image?.bytes;
          if (bytes == null) continue;
          final path = await _storage.saveBytes(bytes, folder: 'pages', ext: '.jpg');
          await _addPage(noteId, path, w, h);
          count++;
        } finally {
          await page.close();
        }
      }
      onProgress?.call(total, total);
    } finally {
      await doc.close();
    }
    return count;
  }

  /// En la compu (pdfx no funciona en Linux) se usa el lector de PDF de
  /// "printing", que va en Windows y Linux.
  Future<int> _importPdfDesktop(String noteId, String pdfPath, {ImportProgress? onProgress}) async {
    final bytes = await File(pdfPath).readAsBytes();
    final info = await Printing.info();
    if (!info.canRaster) throw Exception('No se puede leer el PDF en esta compu.');
    const dpi = 144.0;
    var count = 0;
    await for (final page in Printing.raster(bytes, dpi: dpi)) {
      onProgress?.call(count, count + 1);
      final png = await page.toPng();
      final path = await _storage.saveBytes(png, folder: 'pages', ext: '.png');
      await _addPage(noteId, path, page.width * 72 / dpi, page.height * 72 / dpi);
      count++;
    }
    onProgress?.call(count, count);
    return count;
  }

  /// Fotos de la galería (apuntes, pizarras, libros) como hojas.
  Future<int> importPhotos(String noteId, {ImportProgress? onProgress}) async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 90, maxWidth: 2400);
    for (var i = 0; i < files.length; i++) {
      onProgress?.call(i, files.length);
      final path = await _storage.importFile(files[i].path, folder: 'pages');
      final size = await _imageSize(path);
      await _addPage(noteId, path, size.width, size.height);
    }
    onProgress?.call(files.length, files.length);
    return files.length;
  }

  /// Una imagen (por ejemplo una página de un PDF o una diapositiva) como
  /// hoja nueva al final de la nota, para escribir encima. Devuelve su ruta.
  Future<String> addPageImage(String noteId, String imagePath, double w, double h) async {
    final copy = await _storage.importFile(imagePath, folder: 'pages');
    return _addPage(noteId, copy, w, h);
  }

  Future<String> _addPage(String noteId, String imagePath, double w, double h) async {
    final drawing = Drawing(
      width: Drawing.a4Width,
      height: Drawing.a4Width * h / w, // misma proporción que la página
      paper: PaperStyle(template: PaperTemplate.blank, imagePath: imagePath),
      layers: const [
        // Capa para escribir encima; el fondo (la página) no se borra nunca.
        DrawingLayer(id: 'l1', name: 'Mis notas'),
      ],
    );
    final jsonPath = await _storage.newDrawingPath();
    await _drawings.save(jsonPath, drawing);
    await _notes.addDrawingBlock(noteId, jsonPath);
    return jsonPath;
  }

  static Future<Size> _imageSize(String path) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final size = Size(desc.width.toDouble(), desc.height.toDouble());
    desc.dispose();
    buffer.dispose();
    return size;
  }
}

/// Muestra un diálogo con progreso mientras corre una importación.
Future<T?> runWithProgress<T>(
  BuildContext context,
  String title,
  Future<T> Function(ImportProgress onProgress) task,
) async {
  final progress = ValueNotifier<(int, int)>((0, 0));
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: ValueListenableBuilder<(int, int)>(
        valueListenable: progress,
        builder: (_, v, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2),
            const SizedBox(height: 12),
            Text(v.$2 == 0 ? 'Preparando…' : '${v.$1} de ${v.$2}'),
          ],
        ),
      ),
    ),
  );
  try {
    return await task((done, total) => progress.value = (done, total));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo importar: $e')));
    }
    return null;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
  }
}
