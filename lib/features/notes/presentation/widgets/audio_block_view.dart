import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/time_format.dart';
import '../../../speakers/domain/speaker.dart';
import '../../../transcription/domain/transcript_segment.dart';
import '../../domain/note_block.dart';

/// Grabación con su transcripción en párrafos.
///
/// - Tocar un párrafo → el audio salta a ese momento.
/// - Mantener presionado → editar el texto.
/// - Tocar el nombre → cambiar quién habla.
/// - ⭐ → ver solo las partes marcadas como importantes.
/// - Las fotos tomadas al grabar aparecen en su minuto.
class AudioBlockView extends ConsumerStatefulWidget {
  const AudioBlockView({super.key, required this.block, this.photos = const []});

  final AudioBlock block;
  final List<ImageBlock> photos;

  @override
  ConsumerState<AudioBlockView> createState() => _AudioBlockViewState();
}

class _AudioBlockViewState extends ConsumerState<AudioBlockView> {
  final _player = AudioPlayer();
  bool _onlyImportant = false;

  @override
  void initState() {
    super.initState();
    _player.setFilePath(widget.block.path);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _seek(int ms) async {
    await _player.seek(Duration(milliseconds: ms));
    if (!_player.playing) await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final segments = ref.watch(segmentsProvider(widget.block.id)).valueOrNull ?? const [];
    final markers = ref.watch(markersProvider(widget.block.id)).valueOrNull ?? const [];
    final speakers = {
      for (final s in ref.watch(speakersProvider).valueOrNull ?? const <Speaker>[]) s.id: s,
    };

    final visible = _onlyImportant
        ? segments.where((s) => markers.any(
            (m) => m >= s.startMs - 10000 && m <= s.endMs + 5000)).toList()
        : segments;

    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PlayerBar(
              player: _player,
              durationMs: widget.block.durationMs,
              markers: markers,
              onlyImportant: _onlyImportant,
              onToggleImportant: markers.isEmpty
                  ? null
                  : () => setState(() => _onlyImportant = !_onlyImportant),
            ),
            const Divider(),
            if (segments.isEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Sin transcripción.'),
              ),
              for (final p in widget.photos)
                _PhotoAtTime(photo: p, onTap: () => _seek(p.anchor!.atMs)),
            ],
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snap) {
                final pos = snap.data?.inMilliseconds ?? -1;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      _SegmentTile(
                        segment: visible[i],
                        speaker: speakers[visible[i].speakerId],
                        isCurrent: pos >= visible[i].startMs && pos < visible[i].endMs,
                        isImportant: markers.any((m) =>
                            m >= visible[i].startMs - 10000 && m <= visible[i].endMs + 5000),
                        onTap: () => _seek(visible[i].startMs),
                        onEdit: () => _editText(visible[i]),
                        onSpeakerTap: () => _pickSpeaker(visible[i]),
                        highlight: scheme.primaryContainer,
                      ),
                      ..._photosIn(
                        i == 0 ? 0 : visible[i].startMs,
                        i + 1 < visible.length ? visible[i + 1].startMs : 1 << 31,
                      ).map((p) => _PhotoAtTime(photo: p, onTap: () => _seek(p.anchor!.atMs))),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Iterable<ImageBlock> _photosIn(int fromMs, int toMs) => widget.photos
      .where((p) => p.anchor!.atMs >= fromMs && p.anchor!.atMs < toMs);

  Future<void> _editText(TranscriptSegment s) async {
    final controller = TextEditingController(text: s.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar · ${formatMs(s.startMs)}'),
        content: TextField(controller: controller, maxLines: null, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (result != null && s.id != null) {
      await ref.read(notesRepositoryProvider).updateSegmentText(s.id!, result.trim());
    }
  }

  Future<void> _pickSpeaker(TranscriptSegment s) async {
    final speakers = ref.read(speakersProvider).valueOrNull ?? const <Speaker>[];
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('¿Quién habla aquí?')),
            for (final sp in speakers)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(sp.name),
                onTap: () => Navigator.pop(context, sp.id),
              ),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Otra persona…'),
              onTap: () => Navigator.pop(context, '__new__'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || s.id == null) return;
    var speakerId = choice;
    if (choice == '__new__') {
      if (!mounted) return;
      final name = await askName(context);
      if (name == null) return;
      speakerId = await ref.read(speakersRepositoryProvider).create(name);
    }
    await ref.read(notesRepositoryProvider).updateSegmentSpeaker(s.id!, speakerId);
  }
}

/// Diálogo simple para pedir un nombre (reutilizable).
Future<String?> askName(BuildContext context) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nombre'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Listo')),
      ],
    ),
  );
  final trimmed = name?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({
    required this.player,
    required this.durationMs,
    required this.markers,
    required this.onlyImportant,
    required this.onToggleImportant,
  });

  final AudioPlayer player;
  final int durationMs;
  final List<int> markers;
  final bool onlyImportant;
  final VoidCallback? onToggleImportant;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StreamBuilder<bool>(
          stream: player.playingStream,
          builder: (context, snap) {
            final playing = snap.data ?? false;
            return IconButton.filledTonal(
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: playing ? player.pause : player.play,
            );
          },
        ),
        Expanded(
          child: StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (context, snap) {
              final pos = (snap.data?.inMilliseconds ?? 0).clamp(0, durationMs);
              return Slider(
                value: durationMs == 0 ? 0 : pos / durationMs,
                onChanged: durationMs == 0
                    ? null
                    : (v) => player.seek(Duration(milliseconds: (v * durationMs).round())),
              );
            },
          ),
        ),
        Text(formatMs(durationMs)),
        IconButton(
          tooltip: 'Solo lo importante',
          isSelected: onlyImportant,
          icon: const Icon(Icons.star_border),
          selectedIcon: const Icon(Icons.star),
          onPressed: onToggleImportant,
        ),
      ],
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.segment,
    required this.speaker,
    required this.isCurrent,
    required this.isImportant,
    required this.onTap,
    required this.onEdit,
    required this.onSpeakerTap,
    required this.highlight,
  });

  final TranscriptSegment segment;
  final Speaker? speaker;
  final bool isCurrent;
  final bool isImportant;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onSpeakerTap;
  final Color highlight;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    return InkWell(
      onTap: onTap,
      onLongPress: onEdit,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrent ? highlight : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(formatMs(segment.startMs), style: muted),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onSpeakerTap,
                  child: Text(
                    speaker?.name ?? '¿Quién?',
                    style: muted?.copyWith(decoration: TextDecoration.underline),
                  ),
                ),
                if (isImportant) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.star, size: 14, color: Colors.amber),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(segment.text, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _PhotoAtTime extends StatelessWidget {
  const _PhotoAtTime({required this.photo, required this.onTap});
  final ImageBlock photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(File(photo.path), height: 160, fit: BoxFit.cover),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('📷 ${formatMs(photo.anchor!.atMs)}',
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      );
}
