import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../importing/import_service.dart';
import '../domain/note.dart';
import 'create_note_sheet.dart';
import 'notes_search_delegate.dart';

/// Notas de un cuaderno, o todas si [notebookId] es null.
class NotesListScreen extends ConsumerWidget {
  const NotesListScreen({super.key, this.notebookId});
  final String? notebookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesListProvider(notebookId));
    final notebook =
        notebookId == null ? null : ref.watch(notebookProvider(notebookId!)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(notebookId == null ? 'Todas las notas' : (notebook?.name ?? '')),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar (también dentro de los audios)',
            onPressed: () => showSearch(context: context, delegate: NotesSearchDelegate(ref)),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Importar PDF como nota',
            onPressed: () => _importPdf(context, ref),
          ),
        ],
      ),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _NoteTile(note: list[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nueva nota'),
        onPressed: () => _create(context, ref),
      ),
    );
  }

  /// Crear nota eligiendo la hoja (como en StarNote).
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final opts = await showCreateNoteSheet(context);
    if (opts == null) return;
    final repo = ref.read(notesRepositoryProvider);
    final id = await repo.createNote(title: opts.title, notebookId: notebookId);
    String? sheet;
    if (opts.withSheet) {
      sheet = await ref.read(fileStorageProvider).newDrawingPath();
      await ref.read(drawingStoreProvider).save(sheet, opts.firstPage());
      await repo.addDrawingBlock(id, sheet);
    }
    if (!context.mounted) return;
    context.push('/notes/$id');
    if (sheet != null) context.push('/notes/$id/drawing', extra: sheet);
  }

  Future<void> _importPdf(BuildContext context, WidgetRef ref) async {
    final service = ref.read(importServiceProvider);
    final pdf = await service.pickPdf();
    if (pdf == null || !context.mounted) return;
    final noteId = await runWithProgress(
      context,
      'Importando PDF',
      (onProgress) => service.importPdfAsNewNote(pdf,
          notebookId: notebookId, onProgress: onProgress),
    );
    if (noteId != null && context.mounted) context.push('/notes/$noteId');
  }
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = note.updatedAt;
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) async {
        final files = await ref.read(notesRepositoryProvider).deleteNote(note.id);
        final storage = ref.read(fileStorageProvider);
        for (final f in files) {
          await storage.deleteIfExists(f);
        }
      },
      child: ListTile(
        title: Text(note.displayTitle),
        subtitle: Text(
          '${d.day}/${d.month}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
        ),
        onTap: () => context.push('/notes/${note.id}'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Todavía no hay notas aquí.\nCrea una o importa un PDF.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}
