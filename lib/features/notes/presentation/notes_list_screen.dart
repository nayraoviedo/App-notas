import '../../export/pdf_exporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../drawing/domain/drawing.dart';
import '../../drawing/presentation/drawing_block_view.dart';
import '../../drawing/presentation/painters/paper_painter.dart';
import '../../importing/import_service.dart';
import '../domain/note.dart';
import '../domain/note_block.dart';
import 'create_note_sheet.dart';
import 'note_tags_dialog.dart';
import 'notes_search_delegate.dart';

/// Crear nota eligiendo tapa y hoja (como en StarNote) y abrirla.
Future<void> createNoteFlow(BuildContext context, WidgetRef ref, {String? notebookId}) async {
  final opts = await showCreateNoteSheet(context);
  if (opts == null) return;
  final repo = ref.read(notesRepositoryProvider);
  final id = await repo.createNote(title: opts.title, notebookId: notebookId, tags: opts.tags);
  String? open;
  if (opts.withSheet) {
    final pages = opts.pages();
    for (final page in pages) {
      final path = await ref.read(fileStorageProvider).newDrawingPath();
      await ref.read(drawingStoreProvider).save(path, page);
      await repo.addDrawingBlock(id, path);
      // Se abre en la primera hoja para escribir (después de la tapa).
      if (page.paper.template != PaperTemplate.cover) open ??= path;
    }
  }
  if (!context.mounted) return;
  context.push('/notes/$id');
  if (open != null) context.push('/notes/$id/drawing', extra: open);
}

/// Notas de un cuaderno, o todas si [notebookId] es null, en cuadrícula con
/// la tapa o la primera hoja como portada.
class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key, this.notebookId});
  final String? notebookId;

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  String? _tag;

  @override
  Widget build(BuildContext context) {
    final notebookId = widget.notebookId;
    final notes = ref.watch(notesListProvider(notebookId));
    final notebook = notebookId == null ? null : ref.watch(notebookProvider(notebookId)).valueOrNull;
    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <String>[];

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAFAF9),
        title: Text(notebookId == null ? 'Todas las notas' : (notebook?.name ?? '')),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar (también dentro de los audios)',
            onPressed: () => showSearch(context: context, delegate: NotesSearchDelegate(ref)),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'PDF',
            onSelected: (v) {
              if (v == 'import') _importPdf(context);
              if (v == 'export') {
                exportNotebookFlow(context, ref,
                    notebookId: notebookId,
                    name: notebookId == null ? 'Todas las notas' : (notebook?.name ?? 'Cuaderno'));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export',
                child: ListTile(leading: Icon(Icons.ios_share), title: Text('Exportar a PDF (completo o por notas)')),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(leading: Icon(Icons.file_download_outlined), title: Text('Importar PDF como nota')),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (tags.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Todas'),
                      selected: _tag == null,
                      onSelected: (_) => setState(() => _tag = null),
                    ),
                  ),
                  for (final t in tags)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('#$t'),
                        selected: _tag == t,
                        onSelected: (_) => setState(() => _tag = _tag == t ? null : t),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: notes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                final list = _tag == null ? all : all.where((n) => n.tags.contains(_tag)).toList();
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.56,
                  ),
                  itemCount: list.length + 1,
                  itemBuilder: (context, i) => i == 0
                      ? _CreateTile(onTap: () => createNoteFlow(context, ref, notebookId: notebookId))
                      : _NoteTile(note: list[i - 1]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importPdf(BuildContext context) async {
    final service = ref.read(importServiceProvider);
    final pdf = await service.pickPdf();
    if (pdf == null || !context.mounted) return;
    final noteId = await runWithProgress(
      context,
      'Importando PDF',
      (onProgress) =>
          service.importPdfAsNewNote(pdf, notebookId: widget.notebookId, onProgress: onProgress),
    );
    if (noteId != null && context.mounted) context.push('/notes/$noteId');
  }
}

class _CreateTile extends StatelessWidget {
  const _CreateTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF1E8CB4);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _DashedBorder(accent),
              child: Container(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(child: Icon(Icons.add, size: 48, color: accent)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Crear', style: TextStyle(color: accent, fontSize: 16)),
          const Text('Nueva nota', style: TextStyle(color: Colors.black45, fontSize: 12)),
        ],
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    final path = Path()..addRRect(rrect);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 14) {
        canvas.drawPath(metric.extractPath(d, d + 8), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = note.updatedAt;
    final blocks = ref.watch(blocksProvider(note.id)).valueOrNull ?? const <NoteBlock>[];
    final first = blocks.whereType<DrawingBlock>().firstOrNull;
    // Si tiene hojas, se abre como cuaderno para hojearlo.
    void open() => context.push(first != null ? '/notes/${note.id}/book' : '/notes/${note.id}');

    return Column(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(blurRadius: 6, offset: Offset(0, 2), color: Colors.black26)],
              ),
              child: first != null
                  ? DrawingBlockView(block: first, onOpen: open)
                  : GestureDetector(
                      onTap: open,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: Drawing.a4Width / Drawing.a4Height,
                          child: FittedBox(
                            child: SizedBox(
                              width: Drawing.a4Width,
                              height: Drawing.a4Height,
                              child: PaperView(
                                paper: PaperStyle(
                                  template: PaperTemplate.cover,
                                  background: Paper.coverColors[
                                      note.id.hashCode.abs() % Paper.coverColors.length],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _menu(context, ref),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(note.displayTitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
              ),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
        Text(
          '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}',
          style: const TextStyle(color: Colors.black45, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(note.displayTitle, style: Theme.of(context).textTheme.titleMedium)),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Cambiar nombre'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.tag),
              title: const Text('Etiquetas'),
              subtitle: note.tags.isEmpty ? null : Text(note.tags.map((t) => '#$t').join('  ')),
              onTap: () => Navigator.pop(context, 'tags'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Borrar nota'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    final repo = ref.read(notesRepositoryProvider);
    switch (action) {
      case 'rename':
        final ctl = TextEditingController(text: note.title);
        final name = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Nombre de la nota'),
            content: TextField(controller: ctl, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('Guardar')),
            ],
          ),
        );
        if (name != null) await repo.renameNote(note.id, name.trim());
      case 'tags':
        await showNoteTagsDialog(context, ref, note.id);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('¿Borrar "${note.displayTitle}"?'),
            content: const Text('Se borran sus hojas, audios y fotos.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
            ],
          ),
        );
        if (ok != true) return;
        final files = await repo.deleteNote(note.id);
        final storage = ref.read(fileStorageProvider);
        for (final f in files) {
          await storage.deleteIfExists(f);
        }
    }
  }
}
