import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/fonts.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../drawing/application/drawing_rasterizer.dart';
import '../notes/domain/note_block.dart';
import '../summary/application/summary_runner.dart';

/// Exporta una nota completa a PDF y abre el menú de compartir del teléfono:
/// texto, fotos, hojas a mano (con capas), grabaciones con resumen,
/// capítulos, notas rápidas y transcripción, y notas de video.
Future<void> exportNoteToPdf(WidgetRef ref, String noteId) async {
  final note = await ref.read(noteProvider(noteId).future);
  final blocks = await ref.read(blocksProvider(noteId).future);
  final speakers = {
    for (final s in await ref.read(speakersProvider.future)) s.id: s.name,
  };
  final store = ref.read(drawingStoreProvider);
  final title = note?.displayTitle ?? 'Nota';

  // Si hay texto en chino, el PDF necesita una fuente que lo tenga.
  var needsCjk = hasCjk(title);
  String track(String s) {
    if (!needsCjk && hasCjk(s)) needsCjk = true;
    return s;
  }

  final content = <pw.Widget>[
    pw.Header(level: 0, text: title),
    if (note != null)
      pw.Paragraph(
        text: 'Actualizada: ${note.updatedAt.day}/${note.updatedAt.month}/${note.updatedAt.year}',
        style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
      ),
  ];

  for (final b in blocks) {
    switch (b) {
      case TextBlock t:
        if (t.text.trim().isNotEmpty) content.add(pw.Paragraph(text: track(t.text)));

      case ImageBlock img:
        final f = File(img.path);
        if (!f.existsSync()) continue;
        content.add(pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Column(children: [
            pw.Image(pw.MemoryImage(await f.readAsBytes()),
                fit: pw.BoxFit.contain, height: 360),
            if (img.anchor != null)
              pw.Text('Foto en ${formatMs(img.anchor!.atMs)}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ]),
        ));

      case DrawingBlock dr:
        final d = await store.load(dr.path);
        final png = await rasterizeDrawing(d);
        content
          ..add(pw.NewPage())
          ..add(pw.Center(
            child: pw.Image(pw.MemoryImage(png),
                fit: pw.BoxFit.contain, height: PdfPageFormat.a4.availableHeight - 40),
          ));

      case VideoRefBlock v:
        content.add(pw.Bullet(text: track('Video ${formatMs(v.atMs)}: ${v.text}')));

      case AudioBlock a:
        content.add(pw.Header(level: 1, text: 'Grabación (${formatMs(a.durationMs)})'));
        final summary = await ref.read(summaryProvider(a.id).future);
        if (summary != null) {
          content
            ..add(pw.Header(level: 2, text: track(summary.title)))
            ..add(pw.Paragraph(text: track(summary.overview)));
          for (final k in summary.keyPoints) {
            content.add(pw.Bullet(text: track(k)));
          }
          if (summary.chapters.isNotEmpty) {
            content.add(pw.Header(level: 2, text: 'Capítulos'));
            for (final c in summary.chapters) {
              content
                ..add(pw.Text(track('${formatMs(c.atMs)}  ${c.title}'),
                    style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)))
                ..add(pw.Paragraph(text: track(c.summary)));
            }
          }
        }
        final markers = await ref.read(markersProvider(a.id).future);
        final quick = markers.where((m) => m.isQuickNote).toList();
        if (quick.isNotEmpty) {
          content.add(pw.Header(level: 2, text: 'Notas rápidas'));
          for (final m in quick) {
            content.add(pw.Bullet(text: track('${formatMs(m.atMs)}  ${m.label}')));
          }
        }
        final segments = await ref.read(segmentsProvider(a.id).future);
        if (segments.isNotEmpty) {
          content.add(pw.Header(level: 2, text: 'Transcripción'));
          for (final s in segments) {
            final who = s.speakerId == null ? '' : '${speakers[s.speakerId] ?? ''}: ';
            content.add(pw.Paragraph(
              text: track('[${formatMs(s.startMs)}] $who${s.text}'),
              style: const pw.TextStyle(fontSize: 10.5),
            ));
          }
        }
    }
  }

  pw.ThemeData? theme;
  if (needsCjk) {
    try {
      // Noto Sans SC (Google Fonts) como respaldo para los caracteres chinos.
      theme = pw.ThemeData.withFont(fontFallback: [await PdfGoogleFonts.notoSansSCRegular()]);
    } catch (_) {
      // Sin internet: el PDF se genera igual, pero el chino puede no verse.
    }
  }

  final doc = pw.Document(title: title, theme: theme);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => content,
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('${ctx.pageNumber}/${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    ),
  ));

  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: '${title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim()}.pdf',
  );
}
