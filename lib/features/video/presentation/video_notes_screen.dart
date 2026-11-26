import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
import '../../camera/crop_screen.dart';
import '../../drawing/domain/drawing.dart';
import '../../drawing/presentation/drawing_screen.dart';
import '../../notes/domain/note_block.dart';
import '../../notes/presentation/widgets/text_block_view.dart';
import '../../settings/settings.dart';
import '../data/video_backend.dart';

/// Ver un video y tomar notas al mismo tiempo.
///
/// - Cada nota guarda el minuto del video; al tocarla, el video salta ahí.
/// - El botón de cámara guarda una captura del cuadro actual en la nota
///   (en videos propios y enlaces directos; en YouTube no se puede).
/// - Acepta videos del teléfono, enlaces directos y enlaces de YouTube.
/// - Tres apartados (se desliza entre ellos): Apuntes (texto libre),
///   Notas y capturas (por minuto) y Hoja (a mano, con más hojas).
/// - Pausar al escribir es opcional (botón arriba).
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

class _VideoNotesScreenState extends ConsumerState<VideoNotesScreen> with SingleTickerProviderStateMixin {
  late final VideoBackend _player = VideoBackend.forSource(widget.videoPath);
  late final _tabs = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));
  final _text = TextEditingController();
  final _focus = FocusNode();
  int? _typingAtMs;
  bool _capturing = false;
  bool _creating = false;

  String get _prefKey => 'video.apuntes.${widget.videoPath.hashCode}';

  /// Pausar el video al empezar a escribir (se puede apagar).
  bool get _pauseOnType => ref.read(sharedPreferencesProvider).getBool('video.pauseOnType') ?? false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _open();
  }

  Future<void> _open() async {
    try {
      await _player.open(startMs: widget.startMs);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el video. ¿Hay internet?')),
        );
      }
    }
  }

  Future<void> _onFocus() async {
    if (_focus.hasFocus) {
      // La nota queda en el minuto en que empezaste a escribir.
      _typingAtMs = await _player.positionMs();
      if (_pauseOnType) await _player.pause();
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _text.dispose();
    _tabs.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final atMs = _typingAtMs ?? await _player.positionMs();
    await ref.read(notesRepositoryProvider).addVideoRefBlock(
          widget.noteId,
          videoPath: widget.videoPath,
          atMs: atMs,
          text: text,
        );
    _text.clear();
    _typingAtMs = null;
    if (_pauseOnType) {
      _focus.unfocus();
      await _player.play();
    }
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final atMs = await _player.positionMs();
      final bytes = await _player.screenshot();
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No se pudo capturar este video. Usa la captura del celular y agrégala con 🖼️.')));
        }
        return;
      }
      final path = await ref.read(fileStorageProvider).saveBytes(bytes, folder: 'video_frames', ext: '.jpg');
      final id = await ref.read(notesRepositoryProvider).addImageBlock(
            widget.noteId,
            path,
            anchor: MediaAnchor.video(videoPath: widget.videoPath, atMs: atMs),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('📷 Captura guardada · ${formatMs(atMs)}'),
          action: SnackBarAction(label: 'Recortar', onPressed: () => _crop(id, path)),
        ));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Recortar una captura (o cualquier imagen del video).
  Future<void> _crop(String blockId, String path) async {
    final out = await cropImage(context, path);
    if (out != null && out != path) await ref.read(notesRepositoryProvider).updateImagePath(blockId, out);
  }

  /// Agregar una imagen de la galería (por ejemplo una captura del celular)
  /// en el minuto actual.
  Future<void> _addImage() async {
    final atMs = await _player.positionMs();
    if (!mounted) return;
    final path = await pickAndCropImage(context, ref, camera: false);
    if (path == null) return;
    await ref.read(notesRepositoryProvider).addImageBlock(
          widget.noteId,
          path,
          anchor: MediaAnchor.video(videoPath: widget.videoPath, atMs: atMs),
        );
  }

  Future<void> _editNote(_VideoItem item) async {
    if (item.imagePath != null) {
      final a = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.crop),
                title: const Text('Recortar'),
                onTap: () => Navigator.pop(context, 'crop')),
            ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Borrar'),
                onTap: () => Navigator.pop(context, 'delete')),
          ]),
        ),
      );
      if (a == 'crop') await _crop(item.blockId, item.imagePath!);
      if (a == 'delete') await ref.read(notesRepositoryProvider).deleteBlock(item.blockId);
      return;
    }
    final c = TextEditingController(text: item.text);
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nota en ${formatMs(item.atMs)}'),
        content: TextField(controller: c, autofocus: true, maxLines: null),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, '__delete__'), child: const Text('Borrar')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    if (v == null) return;
    final repo = ref.read(notesRepositoryProvider);
    if (v == '__delete__' || v.isEmpty) {
      await repo.deleteBlock(item.blockId);
    } else {
      await repo.updateText(item.blockId, v);
    }
  }

  /// Bloque de texto libre de este video ("Apuntes"), o null si aún no hay.
  TextBlock? _apuntes(List<NoteBlock> blocks) {
    final id = ref.read(sharedPreferencesProvider).getString(_prefKey);
    return blocks.whereType<TextBlock>().where((b) => b.id == id).firstOrNull;
  }

  Future<void> _createApuntes() async {
    if (_creating) return;
    _creating = true;
    final id = await ref.read(notesRepositoryProvider).addTextBlock(widget.noteId);
    await ref.read(sharedPreferencesProvider).setString(_prefKey, id);
    _creating = false;
    if (mounted) setState(() {});
  }

  /// Hoja del cuaderno para escribir a mano debajo del video.
  Future<void> _createSheet() async {
    if (_creating) return;
    _creating = true;
    final path = await ref.read(fileStorageProvider).newDrawingPath();
    await ref.read(drawingStoreProvider).save(
        path, Drawing.blank(paper: const PaperStyle(template: PaperTemplate.lined)));
    await ref.read(notesRepositoryProvider).addDrawingBlock(widget.noteId, path);
    _creating = false;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = ref.watch(blocksProvider(widget.noteId)).valueOrNull ?? const <NoteBlock>[];
    final items = _itemsForThisVideo(blocks);
    final apuntes = _apuntes(blocks);
    final sheet = blocks.whereType<DrawingBlock>().firstOrNull;
    final onSheet = _tabs.index == 2;

    final videoView = AspectRatio(aspectRatio: 16 / 9, child: _player.view());

    final notesTab = Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              _HelpCard(canCapture: _player.canScreenshot),
              for (final it in items)
                _VideoItemTile(item: it, onSeek: _player.seek, onEdit: () => _editNote(it)),
            ],
          ),
        ),
        _Composer(
          controller: _text,
          focusNode: _focus,
          capturing: _capturing,
          onSend: _addNote,
          onCapture: _player.canScreenshot ? _capture : null,
          onImage: _addImage,
        ),
      ],
    );

    final apuntesTab = apuntes == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Escribe libre, como en un cuaderno: resúmenes, listas, resaltados…',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _createApuntes,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Empezar a escribir'),
                  ),
                ],
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
            children: [TextBlockView(key: ValueKey(apuntes.id), block: apuntes)],
          );

    final sheetTab = sheet == null
        ? Center(
            child: FilledButton.icon(
              onPressed: _createSheet,
              icon: const Icon(Icons.draw_outlined),
              label: const Text('Crear hoja para escribir a mano'),
            ),
          )
        : DrawingScreen(key: ValueKey(sheet.path), noteId: widget.noteId, path: sheet.path, embedded: true);

    final panel = Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Apuntes'),
            Tab(text: 'Notas y capturas'),
            Tab(text: 'Hoja'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            // En la hoja el dedo dibuja: ahí no se desliza entre pestañas.
            physics: onSheet ? const NeverScrollableScrollPhysics() : null,
            children: [apuntesTab, notesTab, sheetTab],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Video + notas'),
        actions: [
          IconButton(
            tooltip: _pauseOnType ? 'Se pausa al escribir (toca para que siga)' : 'Sigue al escribir (toca para pausar)',
            icon: Icon(_pauseOnType ? Icons.pause_circle_outline : Icons.play_circle_outline),
            onPressed: () async {
              await ref.read(sharedPreferencesProvider).setBool('video.pauseOnType', !_pauseOnType);
              if (!mounted) return;
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_pauseOnType
                      ? 'El video se pausará cuando empieces a escribir'
                      : 'El video sigue mientras escribes')));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => c.maxWidth > 720
              // Tablet u horizontal: video y notas lado a lado.
              ? Row(
                  children: [
                    Expanded(flex: 3, child: Center(child: videoView)),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 2, child: panel),
                  ],
                )
              : Column(children: [videoView, Expanded(child: panel)]),
        ),
      ),
    );
  }

  List<_VideoItem> _itemsForThisVideo(List<NoteBlock> blocks) {
    final out = <_VideoItem>[];
    for (final b in blocks) {
      if (b is VideoRefBlock && b.videoPath == widget.videoPath) {
        out.add(_VideoItem(blockId: b.id, atMs: b.atMs, text: b.text));
      } else if (b is ImageBlock && b.anchor?.videoPath == widget.videoPath) {
        out.add(_VideoItem(blockId: b.id, atMs: b.anchor!.atMs, imagePath: b.path));
      }
    }
    out.sort((a, b) => a.atMs.compareTo(b.atMs));
    return out;
  }
}

/// Cómo capturar y recortar (se puede cerrar).
class _HelpCard extends StatefulWidget {
  const _HelpCard({required this.canCapture});
  final bool canCapture;

  @override
  State<_HelpCard> createState() => _HelpCardState();
}

class _HelpCardState extends State<_HelpCard> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.canCapture
                    ? '📷 Capturar: guarda lo que se ve en el video en este minuto. Luego toca '
                        '"Recortar" (o toca la captura) para quedarte solo con una parte.\n'
                        '✏️ Escribe abajo: la nota guarda el minuto; tócala para volver ahí o para editarla.'
                    : 'En YouTube la app no puede capturar el video. Saca captura con el celular '
                        '(bajar volumen + encendido) y agrégala con 🖼️: podrás recortarla y queda en este minuto.\n'
                        '✏️ Escribe abajo: la nota guarda el minuto; tócala para volver ahí o para editarla.',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _hidden = true)),
          ],
        ),
      ),
    );
  }
}

class _VideoItem {
  const _VideoItem({required this.blockId, required this.atMs, this.text, this.imagePath});
  final String blockId;
  final int atMs;
  final String? text;
  final String? imagePath;
}

class _VideoItemTile extends StatelessWidget {
  const _VideoItemTile({required this.item, required this.onSeek, required this.onEdit});
  final _VideoItem item;
  final void Function(int ms) onSeek;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => ListTile(
        // Tocar el minuto lleva ahí; tocar la nota la edita.
        onTap: onEdit,
        leading: ActionChip(
          avatar: const Icon(Icons.play_arrow, size: 16),
          label: Text(formatMs(item.atMs)),
          onPressed: () => onSeek(item.atMs),
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
    required this.onImage,
  });

  final VoidCallback onImage;

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool capturing;
  final VoidCallback onSend;
  /// null en YouTube (no permite capturas).
  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            if (onCapture != null)
              TextButton.icon(
                onPressed: capturing ? null : onCapture,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Capturar'),
              ),
            IconButton(
              tooltip: 'Agregar imagen (captura del celular)',
              onPressed: onImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
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
