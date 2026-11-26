import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as pth;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/fonts.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../backup/drive_sync.dart';
import '../drawing/application/drawing_rasterizer.dart';
import '../settings/settings.dart';
import '../notes/domain/note_block.dart';
import '../recording/application/audio_tools.dart';
import '../summary/application/summary_runner.dart';
import 'docx_writer.dart';

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
  var fmt = 'pdf';
  final how = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Exportar "$name"', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${notes.length} ${notes.length == 1 ? 'nota' : 'notas'}'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pdf', label: Text('PDF')),
                ButtonSegment(value: 'docx', label: Text('Word')),
                ButtonSegment(value: 'md', label: Text('Markdown')),
              ],
              selected: {fmt},
              onSelectionChanged: (v) => set(() => fmt = v.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Cuaderno completo'),
            subtitle: const Text('Todas las notas en un solo archivo, en orden'),
            onTap: () => Navigator.pop(context, 'all'),
          ),
          ListTile(
            leading: const Icon(Icons.file_copy_outlined),
            title: const Text('Cada nota por separado'),
            subtitle: const Text('Un archivo por nota'),
            onTap: () => Navigator.pop(context, 'each'),
          ),
          ListTile(
            leading: const Icon(Icons.checklist),
            title: const Text('Elegir notas…'),
            onTap: () => Navigator.pop(context, 'pick'),
          ),
          ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: const Text('Solo los audios'),
            subtitle: const Text('Todas las grabaciones del cuaderno (m4a)'),
            onTap: () => Navigator.pop(context, 'audio'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add_link),
            title: const Text('Compartir con un link'),
            subtitle: const Text('Se sube como PDF a tu Google Drive y te da un link para mandar'),
            onTap: () => Navigator.pop(context, 'link'),
          ),
        ],
      ),
    ),
    ),
  );
  if (how == null || !context.mounted) return;
  if (how == 'audio') {
    await shareAudiosFlow(context, ref, notes.map((n) => n.id).toList());
    return;
  }
  if (how == 'link') {
    await _shareLinkFlow(context, ref, notes.map((n) => n.id).toList(), name);
    return;
  }
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
                  title: const Text('Juntas en un solo archivo'),
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
    if (fmt == 'md') {
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];
      if (!separate) {
        status.value = 'Armando el Markdown…';
        final parts = ['# $name\n'];
        for (final n in chosen) {
          parts.add(await _noteToMarkdown(ref, n.id, level: 2));
        }
        final f = File('${dir.path}/${safeFileName(name)}.md');
        await f.writeAsString(parts.join('\n\n---\n\n'));
        files.add(XFile(f.path));
      } else {
        for (final (i, n) in chosen.indexed) {
          status.value = 'Nota ${i + 1} de ${chosen.length}…';
          final f = File('${dir.path}/${(i + 1).toString().padLeft(2, '0')} - ${safeFileName(n.displayTitle)}.md');
          await f.writeAsString(await _noteToMarkdown(ref, n.id));
          files.add(XFile(f.path));
        }
      }
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await SharePlus.instance.share(ShareParams(files: files, subject: name));
    } else if (fmt == 'docx') {
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];
      if (!separate) {
        status.value = 'Armando el Word con ${chosen.length} notas…';
        final w = DocxWriter()..heading(name, level: 0);
        for (final (i, n) in chosen.indexed) {
          if (i > 0) w.pageBreak();
          await _noteToDocx(ref, n.id, w);
        }
        final f = File('${dir.path}/${safeFileName(name)}.docx');
        await f.writeAsBytes(w.build());
        files.add(XFile(f.path));
      } else {
        for (final (i, n) in chosen.indexed) {
          status.value = 'Nota ${i + 1} de ${chosen.length}…';
          final w = DocxWriter();
          await _noteToDocx(ref, n.id, w);
          final f = File('${dir.path}/${(i + 1).toString().padLeft(2, '0')} - ${safeFileName(n.displayTitle)}.docx');
          await f.writeAsBytes(w.build());
          files.add(XFile(f.path));
        }
      }
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await SharePlus.instance.share(ShareParams(files: files, subject: name));
    } else if (!separate) {
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

/// Exportar una nota: elegir PDF o Word.
Future<void> exportNoteFlow(BuildContext context, WidgetRef ref, String noteId) async {
  final fmt = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            subtitle: const Text('Para leer, imprimir o compartir tal cual'),
            onTap: () => Navigator.pop(context, 'pdf'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Word (.docx)'),
            subtitle: const Text('Para seguir editándolo en Word o Google Docs'),
            onTap: () => Navigator.pop(context, 'docx'),
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('Markdown (.md)'),
            subtitle: const Text('Texto simple para Notion, Obsidian, GitHub…'),
            onTap: () => Navigator.pop(context, 'md'),
          ),
          ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: const Text('Audios de las grabaciones'),
            subtitle: const Text('Cada grabación como archivo de audio (m4a)'),
            onTap: () => Navigator.pop(context, 'audio'),
          ),
        ],
      ),
    ),
  );
  if (fmt == null) return;
  if (fmt == 'audio') {
    if (context.mounted) await shareAudiosFlow(context, ref, [noteId]);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Preparando…')));
  try {
    if (fmt == 'pdf') {
      await exportNoteToPdf(ref, noteId);
    } else if (fmt == 'md') {
      final note = await ref.read(noteProvider(noteId).future);
      final f = File('${(await getTemporaryDirectory()).path}/${safeFileName(note?.displayTitle ?? 'Nota')}.md');
      await f.writeAsString(await _noteToMarkdown(ref, noteId));
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
    } else {
      final note = await ref.read(noteProvider(noteId).future);
      final w = DocxWriter();
      await _noteToDocx(ref, noteId, w);
      final f = File('${(await getTemporaryDirectory()).path}/${safeFileName(note?.displayTitle ?? 'Nota')}.docx');
      await f.writeAsBytes(w.build());
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
  }
}

Future<(int, int)> _imageSize(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final size = (desc.width, desc.height);
  desc.dispose();
  buffer.dispose();
  return size;
}

/// Una nota en Word: texto, fotos, hojas (como imagen), grabaciones con
/// resumen, notas rápidas y transcripción.
Future<void> _noteToDocx(WidgetRef ref, String noteId, DocxWriter w) async {
  final note = await ref.read(noteProvider(noteId).future);
  final blocks = await ref.read(blocksProvider(noteId).future);
  final speakers = {for (final s in await ref.read(speakersProvider.future)) s.id: s.name};
  final store = ref.read(drawingStoreProvider);
  w.heading(note?.displayTitle ?? 'Nota', level: 1);
  if (note != null) {
    w.paragraph('${note.createdAt.day}/${note.createdAt.month}/${note.createdAt.year}',
        italic: true, halfPoints: 18, color: '777777');
  }
  for (final b in blocks) {
    switch (b) {
      case TextBlock t:
        if (t.text.trim().isNotEmpty) w.paragraph(t.text);
      case ImageBlock img:
        final f = File(img.path);
        if (!f.existsSync()) continue;
        final bytes = await f.readAsBytes();
        final (iw, ih) = await _imageSize(bytes);
        final lower = img.path.toLowerCase();
        if (lower.endsWith('.png')) {
          w.image(bytes, widthPx: iw, heightPx: ih);
        } else {
          w.image(bytes, widthPx: iw, heightPx: ih, jpg: true);
        }
        if (img.anchor != null) {
          w.paragraph('Foto en ${formatMs(img.anchor!.atMs)}', italic: true, halfPoints: 18, color: '777777');
        }
      case DrawingBlock dr:
        final d = await store.load(dr.path);
        final png = await rasterizeDrawing(d);
        w.image(png, widthPx: 1240, heightPx: (1240 * d.height / d.width).round());
      case VideoRefBlock v:
        w.labeled(formatMs(v.atMs), v.text);
      case AudioBlock a:
        w.heading('Grabación (${formatMs(a.durationMs)})', level: 2);
        final summary = await ref.read(summaryProvider(a.id).future);
        if (summary != null) {
          w
            ..heading(summary.title, level: 2)
            ..paragraph(summary.overview);
          for (final k in summary.keyPoints) {
            w.bullet(k);
          }
          for (final c in summary.chapters) {
            w.labeled(formatMs(c.atMs), '${c.title}. ${c.summary}');
          }
        }
        final markers = await ref.read(markersProvider(a.id).future);
        final quick = markers.where((m) => m.isQuickNote).toList();
        if (quick.isNotEmpty) {
          w.heading('Notas rápidas', level: 2);
          for (final m in quick) {
            w.labeled(formatMs(m.atMs), m.label ?? '');
          }
        }
        final segments = await ref.read(segmentsProvider(a.id).future);
        if (segments.isNotEmpty) {
          w.heading('Transcripción', level: 2);
          for (final s in segments) {
            final who = s.speakerId == null ? '' : ' · ${speakers[s.speakerId] ?? ''}';
            w.labeled('${formatMs(s.startMs)}$who', s.text);
          }
        }
    }
  }
}

/// Una nota en Markdown: texto, resumen, notas rápidas y transcripción.
/// Fotos y hojas a mano se indican con una marca (no van adentro del .md).
Future<String> _noteToMarkdown(WidgetRef ref, String noteId, {int level = 1}) async {
  final note = await ref.read(noteProvider(noteId).future);
  final blocks = await ref.read(blocksProvider(noteId).future);
  final speakers = {for (final s in await ref.read(speakersProvider.future)) s.id: s.name};
  final h = '#' * level, h2 = '#' * (level + 1), h3 = '#' * (level + 2);
  final b = StringBuffer('$h ${note?.displayTitle ?? 'Nota'}\n\n');
  if (note != null) {
    b.writeln('_${note.createdAt.day}/${note.createdAt.month}/${note.createdAt.year}_\n');
  }
  var sheets = 0, photos = 0;
  for (final bl in blocks) {
    switch (bl) {
      case TextBlock t:
        if (t.text.trim().isNotEmpty) b.writeln('${t.text.trim()}\n');
      case ImageBlock img:
        photos++;
        b.writeln('_[Foto $photos${img.anchor != null ? ' · ${formatMs(img.anchor!.atMs)}' : ''}]_\n');
      case DrawingBlock _:
        sheets++;
        b.writeln('_[Hoja a mano $sheets]_\n');
      case VideoRefBlock v:
        b.writeln('- **${formatMs(v.atMs)}** ${v.text}');
      case AudioBlock a:
        b.writeln('$h2 Grabación (${formatMs(a.durationMs)})\n');
        final summary = await ref.read(summaryProvider(a.id).future);
        if (summary != null) {
          b.writeln('$h3 ${summary.title}\n\n${summary.overview}\n');
          for (final k in summary.keyPoints) {
            b.writeln('- $k');
          }
          b.writeln();
          for (final c in summary.chapters) {
            b.writeln('- **${formatMs(c.atMs)} ${c.title}:** ${c.summary}');
          }
          b.writeln();
        }
        final quick = (await ref.read(markersProvider(a.id).future)).where((m) => m.isQuickNote).toList();
        if (quick.isNotEmpty) {
          b.writeln('$h3 Notas rápidas\n');
          for (final m in quick) {
            b.writeln('- **${formatMs(m.atMs)}** ${m.label}');
          }
          b.writeln();
        }
        final segments = await ref.read(segmentsProvider(a.id).future);
        if (segments.isNotEmpty) {
          b.writeln('$h3 Transcripción\n');
          for (final s in segments) {
            final who = s.speakerId == null ? '' : ' ${speakers[s.speakerId] ?? ''}:';
            b.writeln('**[${formatMs(s.startMs)}]**$who ${s.text}\n');
          }
        }
    }
  }
  return b.toString().trim();
}


/// Sube el cuaderno como PDF a Google Drive y comparte el link.
Future<void> _shareLinkFlow(BuildContext context, WidgetRef ref, List<String> noteIds, String name) async {
  final status = ValueNotifier<String>('Armando el PDF…');
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 16),
        Expanded(child: ValueListenableBuilder(valueListenable: status, builder: (_, v, __) => Text(v))),
      ]),
    ),
  );
  try {
    final bytes = await buildNotesPdf(ref, noteIds, title: name);
    final link = await DriveSync.instance.shareFile(
      ref.read(sharedPreferencesProvider),
      bytes,
      '${safeFileName(name)}.pdf',
      onStatus: (s) => status.value = s,
    );
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link listo ✓'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ya está copiado. Quien tenga el link puede ver el PDF (no editarlo). '
              'Lo encuentras en tu Drive, carpeta "Kumo compartidos".'),
          const SizedBox(height: 8),
          SelectableText(link, style: const TextStyle(fontSize: 13)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              SharePlus.instance.share(ShareParams(text: '$name 📒 $link', subject: name));
            },
            icon: const Icon(Icons.share),
            label: const Text('Mandar'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo compartir: $e')));
    }
  }
}


/// Comparte los audios de las grabaciones de esas notas (para guardarlos en
/// Drive, Descargas, WhatsApp…).
Future<void> shareAudiosFlow(BuildContext context, WidgetRef ref, List<String> noteIds) async {
  final enhance = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿Cómo quieres los audios?'),
      content: const Text('Mejorado: quita ruido de fondo y zumbidos, y deja el volumen parejo. '
          'Tarda un poco más en prepararse.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Original')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('Mejorado'),
        ),
      ],
    ),
  );
  if (enhance == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Preparando los audios…')));
  try {
    final files = <XFile>[];
    for (final id in noteIds) {
      final note = await ref.read(noteProvider(id).future);
      final title = safeFileName(note?.displayTitle ?? 'Nota');
      final audios = (await ref.read(blocksProvider(id).future)).whereType<AudioBlock>().toList();
      for (var i = 0; i < audios.length; i++) {
        if (!File(audios[i].path).existsSync()) continue;
        final out = await AudioTools.toM4a(audios[i].path, enhance: enhance);
        final suffix = audios.length == 1 ? '' : ' ${i + 1}';
        files.add(XFile(out, name: '$title - grabación$suffix${enhance ? ' (mejorado)' : ''}${pth.extension(out)}'));
      }
    }
    messenger.hideCurrentSnackBar();
    if (files.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('No hay grabaciones aquí')));
      return;
    }
    await SharePlus.instance.share(ShareParams(files: files));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
  }
}
