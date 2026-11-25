import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/fonts.dart';
import '../domain/drawing.dart';
import '../presentation/painters/drawing_painter.dart';
import '../presentation/painters/paper_painter.dart';
import '../presentation/widgets/canvas_item_view.dart' show textItemAlign, textItemStyle;

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
  final practiceFont = d.paper.practice?.font;
  if (practiceFont != null) {
    fontStyle(practiceFont); // asegurar que la fuente china esté cargada
    try {
      await GoogleFonts.pendingFonts();
    } catch (_) {}
  }
  // Fuentes de los textos y fotos del collage.
  final images = <String, ui.Image>{};
  for (final layer in d.layers) {
    for (final it in layer.items) {
      if (it is TextItem && it.font != null) fontStyle(it.font);
      if (it is ImageItem && !images.containsKey(it.path) && File(it.path).existsSync()) {
        final codec = await ui.instantiateImageCodec(await File(it.path).readAsBytes());
        images[it.path] = (await codec.getNextFrame()).image;
      }
    }
  }
  try {
    await GoogleFonts.pendingFonts();
  } catch (_) {}

  PaperPainter(d.paper).paint(canvas, size);
  paintLayers(canvas, size, d, paintItems: (c, layer) {
    c.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, layer.opacity));
    for (final it in layer.items) {
      _paintItem(c, it, images);
    }
    c.restore();
  });
  for (final img in images.values) {
    img.dispose();
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage((d.width * scale).round(), (d.height * scale).round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void _paintItem(Canvas c, CanvasItem it, Map<String, ui.Image> images) {
  c
    ..save()
    ..translate(it.x, it.y)
    ..rotate(it.rotation)
    ..scale(it.scale);
  switch (it) {
    case TextItem t:
      final padX = t.background == null ? 0.0 : t.size * 0.45;
      final padY = t.background == null ? 0.0 : t.size * 0.2;
      final tp = TextPainter(
        text: TextSpan(text: t.text, style: textItemStyle(t)),
        textAlign: textItemAlign(t),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: t.width - padX * 2);
      final box = Rect.fromCenter(
          center: Offset.zero, width: tp.width + padX * 2, height: tp.height + padY * 2);
      if (t.background != null) {
        c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(t.size * 0.2)),
            Paint()..color = Color(t.background!));
      }
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    case ImageItem i:
      final img = images[i.path];
      var rect = Rect.fromCenter(center: Offset.zero, width: i.width, height: i.height);
      if (i.frame == ImageFrame.polaroid) {
        final outer = Rect.fromLTRB(rect.left - 16, rect.top - 16, rect.right + 16, rect.bottom + 60)
            .shift(const Offset(0, -22));
        rect = rect.shift(const Offset(0, -22));
        c.drawRect(outer.shift(const Offset(2, 4)), Paint()..color = const Color(0x33000000));
        c.drawRect(outer, Paint()..color = Colors.white);
      }
      if (img != null) {
        // "cover": recortar la imagen para llenar el rectángulo.
        final iw = img.width.toDouble(), ih = img.height.toDouble();
        final k = (rect.width / rect.height) > (iw / ih) ? iw / rect.width : ih / rect.height;
        final src = Rect.fromCenter(
            center: Offset(iw / 2, ih / 2), width: rect.width * k, height: rect.height * k);
        c.save();
        if (i.frame == ImageFrame.rounded) {
          c.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(28)));
        }
        c.drawImageRect(img, src, rect, Paint()..filterQuality = FilterQuality.medium);
        c.restore();
      }
      if (i.frame == ImageFrame.tape) {
        c.save();
        c.translate(0, rect.top);
        c.rotate(-0.06);
        c.drawRect(Rect.fromCenter(center: Offset.zero, width: i.width * 0.35, height: 34),
            Paint()..color = const Color(0xD9F6D7A7));
        c.restore();
      }
  }
  c.restore();
}
