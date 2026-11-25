import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router.dart';
import '../../../core/widgets/study_timer.dart';
import '../../export/pdf_exporter.dart';
import '../../drawing/domain/drawing.dart';
import '../../drawing/application/practice_builder.dart';
import '../../drawing/presentation/drawing_block_view.dart';
import '../../drawing/presentation/widgets/practice_sheet_dialog.dart';
import '../../importing/import_service.dart';
import '../../notebooks/domain/notebook.dart';
import '../domain/note_block.dart';
import 'widgets/audio_block_view.dart';
import 'widgets/image_block_view.dart';
import 'widgets/text_block_view.dart';
import 'widgets/video_ref_block_view.dart';

class NoteEditorScreen extends ConsumerWidget {
  const NoteEditorScreen({super.key, required this.noteId});
  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(noteProvider(noteId)).valueOrNull;
    final blocks = ref.watch(blocksProvider(noteId));

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _rename(context, ref, note?.title ?? ''),
          child: Text(note?.displayTitle ?? ''),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Cambiar título',
            onPressed: () => _rename(context, ref, note?.title ?? ''),
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move_outline),
            tooltip: 'Mover a cuaderno',
            onPressed: () => _move(context, ref, note?.notebookId),
          ),
          const StudyTimerButton(),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Exportar a PDF',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(const SnackBar(content: Text('Preparando PDF…')));
              try {
                await exportNoteToPdf(ref, noteId);
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
              }
            },
          ),
        ],
      ),
      body: blocks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          // Las fotos tomadas durante una grabación se muestran dentro de esa
          // grabación, en su minuto, no sueltas en la nota.
          // (Si la grabación se borró, la foto vuelve a mostrarse suelta.)
          final audioIds = {for (final b in list) if (b is AudioBlock) b.id};
          bool inAudio(NoteBlock b) =>
              b is ImageBlock && audioIds.contains(b.anchor?.audioBlockId);
          final audioPhotos = <String, List<ImageBlock>>{};
          for (final b in list) {
            if (inAudio(b)) {
              final img = b as ImageBlock;
              audioPhotos.putIfAbsent(img.anchor!.audioBlockId!, () => []).add(img);
            }
          }
          final visible = list.where((b) => !inAudio(b)).toList();

          if (visible.isEmpty) {
            return const Center(
              child: Text('Usa la barra de abajo para escribir, grabar,\n'
                  'tomar fotos o ver un video.', textAlign: TextAlign.center),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: visible.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final b = visible[i];
              final Widget child = switch (b) {
                TextBlock t => TextBlockView(key: ValueKey(t.id), block: t),
                AudioBlock a => AudioBlockView(
                    key: ValueKey(a.id),
                    block: a,
                    photoCount: audioPhotos[a.id]?.length ?? 0,
                    onOpen: () => context.push('/notes/$noteId/audio/${a.id}'),
                  ),
                ImageBlock img => ImageBlockView(
                    key: ValueKey(img.id),
                    block: img,
                    onOpenVideo: (path, ms) => _openVideo(context, path, ms),
                  ),
                DrawingBlock dr => DrawingBlockView(
                    key: ValueKey(dr.id),
                    block: dr,
                    onOpen: () => context.push('/notes/$noteId/drawing', extra: dr.path),
                  ),
                VideoRefBlock v => VideoRefBlockView(
                    key: ValueKey(v.id),
                    block: v,
                    onOpen: () => _openVideo(context, v.videoPath, v.atMs),
                  ),
              };
              final file = switch (b) {
                AudioBlock a => a.path,
                ImageBlock img => img.path,
                DrawingBlock dr => dr.path,
                _ => null,
              };
              return _Deletable(blockId: b.id, filePath: file, child: child);
            },
          );
        },
      ),
      bottomNavigationBar: _EditorToolbar(noteId: noteId, onOpenVideo: _openVideo),
    );
  }

  void _openVideo(BuildContext context, String path, int startMs) {
    context.push('/notes/$noteId/video',
        extra: VideoArgs(videoPath: path, startMs: startMs));
  }

  Future<void> _move(BuildContext context, WidgetRef ref, String? current) async {
    final List<Notebook> notebooks = await ref.read(notebooksProvider.future);
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Mover a…')),
            for (final nb in notebooks)
              ListTile(
                leading: Icon(Icons.book, color: Color(nb.color)),
                title: Text(nb.name),
                trailing: nb.id == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, nb.id),
              ),
            ListTile(
              leading: const Icon(Icons.notes),
              title: const Text('Sin cuaderno'),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, ''),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await ref
        .read(notesRepositoryProvider)
        .moveToNotebook(noteId, choice.isEmpty ? null : choice);
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Título de la nota'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (result != null) {
      await ref.read(notesRepositoryProvider).renameNote(noteId, result.trim());
    }
  }
}

class _Deletable extends ConsumerWidget {
  const _Deletable({required this.blockId, required this.child, this.filePath});
  final String blockId;
  final Widget child;

  /// Archivo del bloque, que se borra junto con él.
  final String? filePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Dismissible(
        key: ValueKey('del-$blockId'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          child: const Icon(Icons.delete_outline),
        ),
        confirmDismiss: (_) async =>
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('¿Borrar este bloque?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('No')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Borrar')),
                ],
              ),
            ) ??
            false,
        onDismissed: (_) async {
          await ref.read(notesRepositoryProvider).deleteBlock(blockId);
          await ref.read(fileStorageProvider).deleteIfExists(filePath);
        },
        child: child,
      );
}

class _EditorToolbar extends ConsumerWidget {
  const _EditorToolbar({required this.noteId, required this.onOpenVideo});
  final String noteId;
  final void Function(BuildContext, String, int) onOpenVideo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(notesRepositoryProvider);
    final camera = ref.read(cameraServiceProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
          children: [
            _ToolButton(
              icon: Icons.notes,
              label: 'Texto',
              onTap: () => repo.addTextBlock(noteId),
            ),
            _ToolButton(
              icon: Icons.draw_outlined,
              label: 'Hoja',
              onTap: () => _newSheet(context, ref, noteId),
            ),
            _ToolButton(
              icon: Icons.mic_none,
              label: 'Grabar',
              onTap: () => context.push('/notes/$noteId/record'),
            ),
            _ToolButton(
              icon: Icons.photo_camera_outlined,
              label: 'Foto',
              onTap: () async {
                final path = await camera.takePhoto();
                if (path != null) await repo.addImageBlock(noteId, path);
              },
            ),
            _ToolButton(
              icon: Icons.image_outlined,
              label: 'Galería',
              onTap: () async {
                final path = await camera.pickImageFromGallery();
                if (path != null) await repo.addImageBlock(noteId, path);
              },
            ),
            _ToolButton(
              icon: Icons.ondemand_video_outlined,
              label: 'Video',
              onTap: () async {
                final path = await camera.pickVideo();
                if (path != null && context.mounted) onOpenVideo(context, path, 0);
              },
            ),
            _ToolButton(
              icon: Icons.file_download_outlined,
              label: 'Importar',
              onTap: () => _import(context, ref, noteId),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Hoja en blanco o práctica de caligrafía china (varias páginas si hace falta).
Future<void> _newSheet(BuildContext context, WidgetRef ref, String noteId) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.draw_outlined),
            title: const Text('Hoja para escribir o dibujar'),
            subtitle: const Text('Después puedes cambiar la plantilla'),
            onTap: () => Navigator.pop(context, 'blank'),
          ),
          ListTile(
            leading: const Text('田', style: TextStyle(fontSize: 24)),
            title: const Text('Práctica de caligrafía china'),
            subtitle: const Text('Caracteres modelo para calcar, con pinyin'),
            onTap: () => Navigator.pop(context, 'practice'),
          ),
        ],
      ),
    ),
  );
  if (kind == null || !context.mounted) return;

  final List<Drawing> pages;
  if (kind == 'practice') {
    final sheet = await showPracticeSheetDialog(context);
    if (sheet == null) return;
    pages = buildPracticePages(sheet);
  } else {
    pages = [Drawing.blank()];
  }

  final storage = ref.read(fileStorageProvider);
  final store = ref.read(drawingStoreProvider);
  final repo = ref.read(notesRepositoryProvider);
  String? first;
  for (final d in pages) {
    final path = await storage.newDrawingPath();
    await store.save(path, d);
    await repo.addDrawingBlock(noteId, path);
    first ??= path;
  }
  if (first != null && context.mounted) {
    context.push('/notes/$noteId/drawing', extra: first);
  }
}

/// Importar PDF o fotos como hojas para escribir encima.
Future<void> _import(BuildContext context, WidgetRef ref, String noteId) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            subtitle: const Text('Cada página se vuelve una hoja para escribir encima'),
            onTap: () => Navigator.pop(context, 'pdf'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Fotos'),
            subtitle: const Text('Apuntes, pizarras o páginas de libros'),
            onTap: () => Navigator.pop(context, 'photos'),
          ),
        ],
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  final service = ref.read(importServiceProvider);
  if (kind == 'pdf') {
    final pdf = await service.pickPdf();
    if (pdf == null || !context.mounted) return;
    await runWithProgress(context, 'Importando PDF',
        (onProgress) => service.importPdf(noteId, pdf, onProgress: onProgress));
  } else {
    await runWithProgress(context, 'Importando fotos',
        (onProgress) => service.importPhotos(noteId, onProgress: onProgress));
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(icon), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 12))],
          ),
        ),
      );
}
