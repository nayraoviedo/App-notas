import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/cat_mascot.dart';
import '../../camera/crop_screen.dart';
import '../../settings/settings.dart';
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
      onCatOptions: (k) => _catOptions(context, ref, k),
    );
  }

  /// Poner la foto real (o el nombre) de un gatito.
  Future<void> _catOptions(BuildContext context, WidgetRef ref, CatKind kind) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final who = kind == CatKind.orange ? 'gatito naranja' : 'gatita gris';
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(catNames.value[kind] ?? 'El $who')),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Poner su foto (galería)'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomarle una foto'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Ponerle nombre'),
              onTap: () => Navigator.pop(context, 'name'),
            ),
            if (catPhotos.value[kind] != null)
              ListTile(
                leading: const Icon(Icons.brush_outlined),
                title: const Text('Volver al dibujo'),
                onTap: () => Navigator.pop(context, 'drawing'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'gallery':
      case 'camera':
        final path = await pickAndCropImage(context, ref, camera: action == 'camera');
        if (path != null) await setCatPhoto(prefs, kind, path);
      case 'name':
        final ctl = TextEditingController(text: catNames.value[kind] ?? '');
        final name = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Cómo se llama?'),
            content: TextField(controller: ctl, autofocus: true, textCapitalization: TextCapitalization.words),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('Guardar')),
            ],
          ),
        );
        if (name != null) await setCatName(prefs, kind, name);
      case 'drawing':
        await setCatPhoto(prefs, kind, null);
    }
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

