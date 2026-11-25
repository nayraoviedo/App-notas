import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router.dart';
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
        ],
      ),
      body: blocks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          // Las fotos tomadas durante una grabación se muestran dentro de esa
          // grabación, en su minuto, no sueltas en la nota.
          final audioPhotos = <String, List<ImageBlock>>{};
          for (final b in list) {
            if (b is ImageBlock && b.anchor?.isAudio == true) {
              audioPhotos.putIfAbsent(b.anchor!.audioBlockId!, () => []).add(b);
            }
          }
          final visible = list
              .where((b) => !(b is ImageBlock && b.anchor?.isAudio == true))
              .toList();

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
              final child = switch (b) {
                TextBlock t => TextBlockView(key: ValueKey(t.id), block: t),
                AudioBlock a => AudioBlockView(
                    key: ValueKey(a.id),
                    block: a,
                    photos: audioPhotos[a.id] ?? const [],
                  ),
                ImageBlock img => ImageBlockView(
                    key: ValueKey(img.id),
                    block: img,
                    onOpenVideo: (path, ms) => _openVideo(context, path, ms),
                  ),
                VideoRefBlock v => VideoRefBlockView(
                    key: ValueKey(v.id),
                    block: v,
                    onOpen: () => _openVideo(context, v.videoPath, v.atMs),
                  ),
              };
              return _Deletable(blockId: b.id, child: child);
            },
          );
        },
      ),
      bottomNavigationBar: _EditorToolbar(noteId: noteId, onOpenVideo: _openVideo),
    );
  }

  void _openVideo(BuildContext context, String path, int startMs) {
    context.go('/notes/$noteId/video',
        extra: VideoArgs(videoPath: path, startMs: startMs));
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
  const _Deletable({required this.blockId, required this.child});
  final String blockId;
  final Widget child;

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
        onDismissed: (_) => ref.read(notesRepositoryProvider).deleteBlock(blockId),
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ToolButton(
              icon: Icons.notes,
              label: 'Texto',
              onTap: () => repo.addTextBlock(noteId),
            ),
            _ToolButton(
              icon: Icons.mic_none,
              label: 'Grabar',
              onTap: () => context.go('/notes/$noteId/record'),
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
          ],
        ),
      ),
    );
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
