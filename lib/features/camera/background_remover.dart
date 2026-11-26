import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/platform_info.dart';

/// Quita el fondo de una foto: deja solo a la persona, mascota u objeto
/// principal (ML Kit de Google, funciona en el teléfono, sin internet una vez
/// descargado el modelo).
class BackgroundRemovalException implements Exception {
  const BackgroundRemovalException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<ui.Image> removeBackground(ui.Image image) async {
  if (!isPhone) throw Exception('Quitar el fondo solo funciona en el celular por ahora.');
  final w = image.width, h = image.height;
  // ML Kit lee desde un archivo: se guarda la imagen tal como se ve (ya
  // girada) para que la máscara coincida píxel a píxel.
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  if (png == null || rgba == null) throw const BackgroundRemovalException('No se pudo leer la foto.');
  final dir = await getTemporaryDirectory();
  final tmp = File('${dir.path}/sin_fondo_${DateTime.now().microsecondsSinceEpoch}.png');
  await tmp.writeAsBytes(png.buffer.asUint8List(), flush: true);

  final segmenter = SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundBitmap: false,
      enableForegroundConfidenceMask: true,
      enableMultipleSubjects: SubjectResultOptions(
        enableConfidenceMask: false,
        enableSubjectBitmap: false,
      ),
    ),
  );
  List<double>? mask;
  try {
    final result = await segmenter.processImage(InputImage.fromFilePath(tmp.path));
    mask = result.foregroundConfidenceMask;
  } catch (e) {
    final msg = '$e'.toLowerCase();
    throw BackgroundRemovalException(msg.contains('download') || msg.contains('module')
        ? 'Se está descargando la herramienta para quitar fondos. Prueba de nuevo en un minuto (con internet).'
        : 'No se pudo quitar el fondo: $e');
  } finally {
    await segmenter.close();
    tmp.delete().ignore();
  }
  if (mask == null || mask.isEmpty) {
    throw const BackgroundRemovalException('No encontré a nadie ni nada en primer plano en esta foto.');
  }
  final pixels = await compute(applyMask, (rgba.buffer.asUint8List(), mask, w, h));
  return _decode(pixels, w, h);
}

/// Aplica la máscara (0..1 por píxel) al canal alfa. Si la máscara viene en
/// otro tamaño, se escala.
Uint8List applyMask((Uint8List, List<double>, int, int) args) {
  final (src, mask, w, h) = args;
  final out = Uint8List.fromList(src);
  var mw = w, mh = h;
  if (mask.length != w * h) {
    // Misma proporción que la foto, otro tamaño.
    mw = math.max(1, math.sqrt(mask.length * w / h).round());
    mh = math.max(1, mask.length ~/ mw);
  }
  for (var y = 0; y < h; y++) {
    final my = mh == h ? y : (y * mh ~/ h).clamp(0, mh - 1);
    for (var x = 0; x < w; x++) {
      final mx = mw == w ? x : (x * mw ~/ w).clamp(0, mw - 1);
      final i = my * mw + mx;
      final m = i < mask.length ? mask[i] : 0.0;
      // Borde suave: < 0.35 transparente, > 0.65 opaco.
      final a = ((m - 0.35) / 0.3).clamp(0.0, 1.0);
      final p = (y * w + x) * 4 + 3;
      out[p] = (out[p] * a).round();
    }
  }
  return out;
}

Future<ui.Image> _decode(Uint8List pixels, int w, int h) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final desc = ui.ImageDescriptor.raw(buffer, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await desc.instantiateCodec();
  final frame = await codec.getNextFrame();
  codec.dispose();
  desc.dispose();
  buffer.dispose();
  return frame.image;
}
