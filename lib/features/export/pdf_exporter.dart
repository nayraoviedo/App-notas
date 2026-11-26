import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
  final (title, bytes) = await buildNotePdf(ref, noteId);
  await Printing.sharePdf(bytes: bytes, filename: '${safeFileName(title)}.pdf');
}

String safeFileName(String s) {
  final t = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
  return t.isEmpty ? 'Nota' : t;
}

/// Varias notas en un solo PDF (un cuaderno completo), cada nota empieza en
/// hoja nueva. Devuelve los bytes.
Future<Uint8List> buildNotesPdf(WidgetRef ref, List<String> noteIds, {required String title}) async {
  final content = <pw.Widget>[];
  var needsCjk = hasCjk(title);
  for (final (i, id) in noteIds.indexed) {
    final (part, cjk) = await _noteContent(ref, id);
    needsCjk = needsCjk || cjk;
    if (i > 0) content.add(pw.NewPage());
    content.addAll(part);
  }
  return _render(content, title: title, needsCjk: needsCjk);
}

/// Una nota a PDF: (título, bytes).
Future<(String, Uint8List)> buildNotePdf(WidgetRef ref, String noteId) async {
  final note = await ref.read(noteProvider(noteId).future);
  final title = note?.displayTitle ?? 'Nota';
  final (content, cjk) = await _noteContent(ref, noteId);
  return (title, await _render(content, title: title, needsCjk: cjk));
}

Future<(List<pw.Widget>, bool)> _noteContent(WidgetRef ref, String noteId) async {
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

  return (content, needsCjk);
}

Future<Uint8List> _render(List<pw.Widget> content, {required String title, required bool needsCjk}) async {
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
    maxPages: 2000,
    build: (_) => content,
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('${ctx.pageNumber}/${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    ),
  ));
  return doc.save();
}

/// Exportar un cuaderno (o todas las notas si [notebookId] es null): completo
/// en un PDF, cada nota en su PDF, o solo algunas notas.
Future<void> exportNotebookFlow(BuildContext context, WidgetRef ref, {String? notebookId, required String name}) async {
  final notes = (await ref.read(notesRepositoryProvider).watchNotes(notebookId: notebookId).first).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  if (!context.mounted) return;
  if (notes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este cuaderno no tiene notas.')));
    return;
  }
  final how = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Exportar "$name" a PDF', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${notes.length} ${notes.length == 1 ? 'nota' : 'notas'}'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Cuaderno completo'),
            subtitle: const Text('Todas las notas en un solo PDF, en orden'),
            onTap: () => Navigator.pop(context, 'all'),
          ),
          ListTile(
            leading: const Icon(Icons.file_copy_outlined),
            title: const Text('Cada nota por separado'),
            subtitle: const Text('Un PDF por nota'),
            onTap: () => Navigator.pop(context, 'each'),
          ),
          ListTile(
            leading: const Icon(Icons.checklist),
            title: const Text('Elegir notas…'),
            onTap: () => Navigator.pop(context, 'pick'),
          ),
        ],
      ),
    ),
  );
  if (how == null || !context.mounted) return;
  var chosen = notes;
  var separate = how == 'each';
  if (how == 'pick') {
    final sel = <String>{};
    var together = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('¿Qué notas?'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final n in notes)
                  CheckboxListTile(
                    value: sel.contains(n.id),
                    title: Text(n.displayTitle),
                    subtitle: Text('${n.createdAt.day}/${n.createdAt.month}/${n.createdAt.year}'),
                    onChanged: (v) => set(() => v == true ? sel.add(n.id) : sel.remove(n.id)),
                  ),
                SwitchListTile(
                  title: const Text('Juntas en un solo PDF'),
                  value: together,
                  onChanged: (v) => set(() => together = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Exportar')),
          ],
        ),
      ),
    );
    if (ok != true || sel.isEmpty || !context.mounted) return;
    chosen = notes.where((n) => sel.contains(n.id)).toList();
    separate = !together;
  }

  final status = ValueNotifier<String>('Preparando…');
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: ValueListenableBuilder(valueListenable: status, builder: (_, v, __) => Text(v))),
        ],
      ),
    ),
  );
  try {
    if (!separate) {
      status.value = 'Armando el PDF con ${chosen.length} notas…';
      final bytes = await buildNotesPdf(ref, [for (final n in chosen) n.id], title: name);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await Printing.sharePdf(bytes: bytes, filename: '${safeFileName(name)}.pdf');
    } else {
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];
      for (final (i, n) in chosen.indexed) {
        status.value = 'Nota ${i + 1} de ${chosen.length}…';
        final (title, bytes) = await buildNotePdf(ref, n.id);
        final f = File('${dir.path}/${(i + 1).toString().padLeft(2, '0')} - ${safeFileName(title)}.pdf');
        await f.writeAsBytes(bytes);
        files.add(XFile(f.path));
      }
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await SharePlus.instance.share(ShareParams(files: files, subject: name));
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }
}
