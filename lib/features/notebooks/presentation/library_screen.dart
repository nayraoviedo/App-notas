import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../importing/import_service.dart';
import '../../notes/presentation/notes_list_screen.dart';
import '../../notes/presentation/notes_search_delegate.dart';
import '../domain/notebook.dart';
import 'home_view.dart';
import 'notebook_form.dart';

export 'home_view.dart';

/// Pantalla de inicio: estantería de cuadernos en carrusel (o cuadrícula),
/// accesos rápidos y los gatitos.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = ref.watch(notebooksProvider).valueOrNull;
    final counts = ref.watch(notebookCountsProvider).valueOrNull ?? const {};
    final notesCount = ref.watch(notesListProvider(null)).valueOrNull?.length ?? 0;

    return HomeView(
      notebooks: notebooks,
      counts: counts,
      notesCount: notesCount,
      onOpenNotebook: (nb) => context.push('/notebooks/${nb.id}'),
      onNotebookOptions: (nb) => _options(context, ref, nb),
      onNewNotebook: () => _create(context, ref),
      onAllNotes: () => context.push('/notebooks/all'),
      onSearch: () => showSearch(context: context, delegate: NotesSearchDelegate(ref)),
      onSettings: () => context.push('/settings'),
      onAdd: () => _addMenu(context, ref),
    );
  }

  Future<void> _addMenu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note, color: HomeColors.terracotta),
              title: const Text('Nueva nota'),
              subtitle: const Text('Elige tapa y hoja'),
              onTap: () => Navigator.pop(context, 'note'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined, color: HomeColors.terracotta),
              title: const Text('Nuevo cuaderno'),
              subtitle: const Text('Para agrupar tus notas'),
              onTap: () => Navigator.pop(context, 'notebook'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: HomeColors.terracotta),
              title: const Text('Importar PDF'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'note':
        await createNoteFlow(context, ref);
      case 'notebook':
        await _create(context, ref);
      case 'pdf':
        final service = ref.read(importServiceProvider);
        final pdf = await service.pickPdf();
        if (pdf == null || !context.mounted) return;
        final id = await runWithProgress(
            context, 'Importando PDF', (p) => service.importPdfAsNewNote(pdf, onProgress: p));
        if (id != null && context.mounted) context.push('/notes/$id');
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final r = await showNotebookForm(
      context,
      pickCover: ref.read(cameraServiceProvider).pickImageFromGallery,
    );
    if (r == null) return;
    await ref
        .read(notebooksRepositoryProvider)
        .create(r.name, color: r.color, coverPath: r.coverPath, style: r.style);
  }

  Future<void> _options(BuildContext context, WidgetRef ref, Notebook nb) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar nombre, color o portada'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Eliminar cuaderno'),
              subtitle: const Text('Las notas no se borran: quedan en "Todas las notas"'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    final repo = ref.read(notebooksRepositoryProvider);
    if (action == 'edit') {
      final r = await showNotebookForm(
        context,
        initial: nb,
        pickCover: ref.read(cameraServiceProvider).pickImageFromGallery,
      );
      if (r != null) {
        await repo.update(nb.id, name: r.name, color: r.color, coverPath: r.coverPath, style: r.style);
      }
    } else if (action == 'delete') {
      await repo.delete(nb.id);
    }
  }
}

