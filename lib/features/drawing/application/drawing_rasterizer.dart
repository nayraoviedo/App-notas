import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/drawing.dart';
import '../presentation/painters/drawing_painter.dart';
import '../presentation/painters/paper_painter.dart';

/// Convierte una hoja (fondo + capas) en una imagen PNG, para exportar.
Future<Uint8List> rasterizeDrawing(Drawing d, {double pixelWidth = 1240}) async {
  final scale = pixelWidth / d.width;
  final size = Size(d.width, d.height);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);

  canvas.drawRect(Offset.zero & size, Paint()..color = Color(d.paper.background));
  final imagePath = d.paper.imagePath;
  if (imagePath != null && File(imagePath).existsSync()) {
    final codec = await ui.instantiateImageCodec(await File(imagePath).readAsBytes());
    final frame = await codec.getNextFrame();
    final img = frame.image;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    img.dispose();
  }
  PaperPainter(d.paper).paint(canvas, size);
  paintLayers(canvas, size, d);

  final picture = recorder.endRecording();
  final image = await picture.toImage((d.width * scale).round(), (d.height * scale).round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}
