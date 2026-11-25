import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
import '../../notes/domain/note_block.dart';

/// Ver un video y tomar notas al mismo tiempo.
///
/// - Cada nota guarda el minuto del video; al tocarla, el video salta ahí.
/// - El botón de cámara guarda una captura del cuadro actual en la nota.
/// - Al empezar a escribir, el video se pausa (y la nota queda con el minuto
///   en que empezaste a escribir, no en el que terminaste).
class VideoNotesScreen extends ConsumerStatefulWidget {
  const VideoNotesScreen({
    super.key,
    required this.noteId,
    required this.videoPath,
    this.startMs = 0,
  });

  final String noteId;
  final String videoPath;
  final int startMs;

  @override
  ConsumerState<VideoNotesScreen> createState() => _VideoNotesScreenState();
}

class _VideoNotesScreenState extends ConsumerState<VideoNotesScreen> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final _text = TextEditingController();
  final _focus = FocusNode();
  int? _typingAtMs;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _open();
  }

  Future<void> _open() async {
    await _player.open(Media(widget.videoPath), play: false);
    if (widget.startMs > 0) {
      // Esperar a que el video sepa su duración antes de saltar.
      await _player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 5), onTimeout: () => Duration.zero);
      await _player.seek(Duration(milliseconds: widget.startMs));
    }
    await _player.play();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _typingAtMs = _player.state.position.inMilliseconds;
      _player.pause();
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _text.dispose();
    _player.dispose();
    super.dispose();
  }

  int get _nowMs => _player.state.position.inMilliseconds;

  Future<void> _addNote() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    await ref.read(notesRepositoryProvider).addVideoRefBlock(
          widget.noteId,
          videoPath: widget.videoPath,
          atMs: _typingAtMs ?? _nowMs,
          text: text,
        );
    _text.clear();
    _typingAtMs = null;
    _focus.unfocus();
    await _player.play();
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final atMs = _nowMs;
      final bytes = await _player.screenshot();
      if (bytes == null) return;
      final path = await ref
          .read(fileStorageProvider)
          .saveBytes(bytes, folder: 'video_frames', ext: '.jpg');
      await ref.read(notesRepositoryProvider).addImageBlock(
            widget.noteId,
            path,
            anchor: MediaAnchor.video(videoPath: widget.videoPath, atMs: atMs),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Captura guardada · ${formatMs(atMs)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocks = ref.watch(blocksProvider(widget.noteId)).valueOrNull ?? const [];
    final items = _itemsForThisVideo(blocks);

    final videoView = AspectRatio(
      aspectRatio: 16 / 9,
      child: Video(controller: _video),
    );
    final notesPanel = Column(
      children: [
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('Escribe abajo o toma una captura 📷'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => _VideoItemTile(
                    item: items[i],
                    onSeek: (ms) => _player.seek(Duration(milliseconds: ms)),
                  ),
                ),
        ),
        _Composer(
          controller: _text,
          focusNode: _focus,
          capturing: _capturing,
          onSend: _addNote,
          onCapture: _capture,
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Video + notas')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => c.maxWidth > 720
              // Tablet u horizontal: video y notas lado a lado.
              ? Row(
                  children: [
                    Expanded(flex: 3, child: Center(child: videoView)),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 2, child: notesPanel),
                  ],
                )
              : Column(children: [videoView, Expanded(child: notesPanel)]),
        ),
      ),
    );
  }

  List<_VideoItem> _itemsForThisVideo(List<NoteBlock> blocks) {
    final out = <_VideoItem>[];
    for (final b in blocks) {
      if (b is VideoRefBlock && b.videoPath == widget.videoPath) {
        out.add(_VideoItem(atMs: b.atMs, text: b.text));
      } else if (b is ImageBlock && b.anchor?.videoPath == widget.videoPath) {
        out.add(_VideoItem(atMs: b.anchor!.atMs, imagePath: b.path));
      }
    }
    out.sort((a, b) => a.atMs.compareTo(b.atMs));
    return out;
  }
}

class _VideoItem {
  const _VideoItem({required this.atMs, this.text, this.imagePath});
  final int atMs;
  final String? text;
  final String? imagePath;
}

class _VideoItemTile extends StatelessWidget {
  const _VideoItemTile({required this.item, required this.onSeek});
  final _VideoItem item;
  final void Function(int ms) onSeek;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: () => onSeek(item.atMs),
        leading: Text(
          formatMs(item.atMs),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        title: item.imagePath != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(item.imagePath!), height: 120, fit: BoxFit.cover),
              )
            : Text(item.text ?? ''),
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.capturing,
    required this.onSend,
    required this.onCapture,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool capturing;
  final VoidCallback onSend;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Captura del video',
              onPressed: capturing ? null : onCapture,
              icon: const Icon(Icons.photo_camera_outlined),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Nota en este minuto…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            IconButton(onPressed: onSend, icon: const Icon(Icons.send)),
          ],
        ),
      );
}
