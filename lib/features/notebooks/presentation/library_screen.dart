import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../notes/presentation/notes_search_delegate.dart';
import '../domain/notebook.dart';
import 'notebook_form.dart';

/// Pantalla principal: estantería de cuadernos.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = ref.watch(notebooksProvider);
    final counts = ref.watch(notebookCountsProvider).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis cuadernos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar (también dentro de los audios)',
            onPressed: () => showSearch(context: context, delegate: NotesSearchDelegate(ref)),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ajustes',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: notebooks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            mainAxisSpacing: 24,
            crossAxisSpacing: 20,
            childAspectRatio: 0.58,
          ),
          itemCount: list.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) {
              return _ShelfItem(
                cover: LayoutBuilder(
                  builder: (_, c) => NotebookCover(
                    name: 'Todas las notas',
                    color: 0xFFCDB4DB,
                    style: const CoverStyle(pattern: CoverPattern.gingham, sticker: ''),
                    width: c.maxWidth,
                    icon: Icons.notes,
                  ),
                ),
                subtitle: '',
                onTap: () => context.push('/notebooks/all'),
              );
            }
            if (i == list.length + 1) {
              return _ShelfItem(
                cover: LayoutBuilder(
                  builder: (_, c) => _NewNotebookCover(width: c.maxWidth),
                ),
                subtitle: '',
                onTap: () => _create(context, ref),
              );
            }
            final nb = list[i - 1];
            final n = counts[nb.id] ?? 0;
            return _ShelfItem(
              cover: LayoutBuilder(
                builder: (_, c) => NotebookCover(
                  name: nb.name,
                  color: nb.color,
                  coverPath: nb.coverPath,
                  style: nb.style,
                  width: c.maxWidth,
                ),
              ),
              subtitle: n == 1 ? '1 nota' : '$n notas',
              onTap: () => context.push('/notebooks/${nb.id}'),
              onLongPress: () => _options(context, ref, nb),
            );
          },
        ),
      ),
    );
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
        await repo.update(nb.id,
            name: r.name, color: r.color, coverPath: r.coverPath, style: r.style);
      }
    } else if (action == 'delete') {
      await repo.delete(nb.id);
    }
  }
}

class _ShelfItem extends StatelessWidget {
  const _ShelfItem({
    required this.cover,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  final Widget cover;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          children: [
            Expanded(child: Align(alignment: Alignment.bottomCenter, child: cover)),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _NewNotebookCover extends StatelessWidget {
  const _NewNotebookCover({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: width * 1.35,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.5),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(Icons.add, size: 36), SizedBox(height: 6), Text('Nuevo cuaderno')],
        ),
      );
}
