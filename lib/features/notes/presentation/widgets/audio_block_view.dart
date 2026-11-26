import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/providers.dart';
import '../../../../core/utils/time_format.dart';
import '../../../speakers/domain/speaker.dart';
import '../../../settings/settings.dart';
import '../../../transcription/application/segment_merger.dart';
import '../../../transcription/domain/transcript_segment.dart';
import '../../../study/presentation/study_screen.dart' show showNewFlashcard;
import '../../../transcription/domain/transcription_service.dart';
import '../../domain/note_block.dart';

/// Tarjeta compacta de una grabación dentro de la nota: reproductor, los
/// primeros párrafos y un botón para abrir la vista completa
/// (Transcripción / Notas rápidas / Resumen).
class AudioBlockView extends ConsumerStatefulWidget {
  const AudioBlockView({
    super.key,
    required this.block,
    required this.onOpen,
    this.photoCount = 0,
  });

  final AudioBlock block;
  final VoidCallback onOpen;
  final int photoCount;

  @override
  ConsumerState<AudioBlockView> createState() => _AudioBlockViewState();
}

class _AudioBlockViewState extends ConsumerState<AudioBlockView> {
  final _player = AudioPlayer();

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

  @override
  Widget build(BuildContext context) {
    final segments = ref.watch(segmentsProvider(widget.block.id)).valueOrNull ?? const [];
    final markers = ref.watch(markersProvider(widget.block.id)).valueOrNull ?? const [];
    final preview = segments.take(3).map((s) => s.text).join(' ');
    final notes = markers.where((m) => m.isQuickNote).length;
    final stars = markers.length - notes;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlayerBar(player: _player, durationMs: widget.block.durationMs, compact: true),
              if (preview.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
              Row(
                children: [
                  if (stars > 0) Text('⭐ $stars   '),
                  if (notes > 0) Text('📝 $notes   '),
                  if (widget.photoCount > 0) Text('📷 ${widget.photoCount}'),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_full, size: 18),
                    label: const Text('Transcripción y resumen'),
                    onPressed: widget.onOpen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Transcripción completa en párrafos.
///
/// - Tocar un párrafo → el audio salta a ese momento.
/// - Mantener presionado → editar el texto.
/// - Tocar el nombre → cambiar quién habla.
/// - Las fotos tomadas al grabar aparecen en su minuto.
class TranscriptView extends ConsumerWidget {
  const TranscriptView({
    super.key,
    required this.blockId,
    required this.player,
    this.photos = const [],
    this.onlyImportant = false,
    this.audioPath,
  });

  final String blockId;

  /// Archivo de audio, para poder transcribir de nuevo si quedó vacío.
  final String? audioPath;
  final AudioPlayer player;
  final List<ImageBlock> photos;
  final bool onlyImportant;

  Future<void> _seek(int ms) async {
    await player.seek(Duration(milliseconds: ms));
    if (!player.playing) await player.play();
  }

  bool _important(TranscriptSegment s, List<AudioMarker> markers) =>
      markers.any((m) => m.atMs >= s.startMs - 10000 && m.atMs <= s.endMs + 5000);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segments = ref.watch(segmentsProvider(blockId)).valueOrNull ?? const [];
    final markers = ref.watch(markersProvider(blockId)).valueOrNull ?? const [];
    final speakers = {
      for (final s in ref.watch(speakersProvider).valueOrNull ?? const <Speaker>[]) s.id: s,
    };
    final visible =
        onlyImportant ? segments.where((s) => _important(s, markers)).toList() : segments;
    final highlight = Theme.of(context).colorScheme.primaryContainer;

    if (segments.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Sin transcripción.'),
          if (audioPath != null) ...[
            const SizedBox(height: 12),
            TranscribeNowButton(blockId: blockId, audioPath: audioPath!),
          ],
          for (final p in photos) _PhotoAtTime(photo: p, onTap: () => _seek(p.anchor!.atMs)),
        ],
      );
    }

    Iterable<ImageBlock> photosIn(int fromMs, int toMs) =>
        photos.where((p) => p.anchor!.atMs >= fromMs && p.anchor!.atMs < toMs);

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final pos = snap.data?.inMilliseconds ?? -1;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final s = visible[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SegmentTile(
                  segment: s,
                  speaker: speakers[s.speakerId],
                  isCurrent: pos >= s.startMs && pos < s.endMs,
                  isImportant: _important(s, markers),
                  onTap: () => _seek(s.startMs),
                  onEdit: () => _segmentMenu(context, ref, s),
                  onSpeakerTap: () => _pickSpeaker(context, ref, s),
                  highlight: highlight,
                ),
                ...photosIn(
                  i == 0 ? 0 : s.startMs,
                  i + 1 < visible.length ? visible[i + 1].startMs : 1 << 31,
                ).map((p) => _PhotoAtTime(photo: p, onTap: () => _seek(p.anchor!.atMs))),
              ],
            );
          },
        );
      },
    );
  }

  /// Mantener presionada una frase: editarla o volverla tarjeta de repaso.
  Future<void> _segmentMenu(BuildContext context, WidgetRef ref, TranscriptSegment s) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar texto'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.style_outlined),
              title: const Text('Crear tarjeta de repaso'),
              subtitle: const Text('Esta frase será la respuesta'),
              onTap: () => Navigator.pop(context, 'card'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'edit') await _editText(context, ref, s);
    if (action == 'card') await showNewFlashcard(context, ref, back: '${s.text.trim()} (${formatMs(s.startMs)})');
  }

  Future<void> _editText(BuildContext context, WidgetRef ref, TranscriptSegment s) async {
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

  Future<void> _pickSpeaker(BuildContext context, WidgetRef ref, TranscriptSegment s) async {
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
      if (!context.mounted) return;
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

/// Reproductor: velocidad, ±10 s, play/pausa y barra de progreso.
class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    required this.player,
    required this.durationMs,
    this.compact = false,
  });

  final AudioPlayer player;
  final int durationMs;

  /// Versión de una sola fila para la tarjeta dentro de la nota.
  final bool compact;

  static const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  Future<void> _skip(int deltaMs) async {
    final target = (player.position.inMilliseconds + deltaMs).clamp(0, durationMs);
    await player.seek(Duration(milliseconds: target));
  }

  @override
  Widget build(BuildContext context) {
    final playButton = StreamBuilder<bool>(
      stream: player.playingStream,
      builder: (context, snap) {
        final playing = snap.data ?? false;
        return IconButton.filled(
          iconSize: compact ? 24 : 34,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: playing ? player.pause : player.play,
        );
      },
    );

    final slider = StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final pos = (snap.data?.inMilliseconds ?? 0).clamp(0, durationMs);
        return Row(
          children: [
            Text(formatMs(pos), style: Theme.of(context).textTheme.bodySmall),
            Expanded(
              child: Slider(
                value: durationMs == 0 ? 0 : pos / durationMs,
                onChanged: durationMs == 0
                    ? null
                    : (v) => player.seek(Duration(milliseconds: (v * durationMs).round())),
              ),
            ),
            Text(formatMs(durationMs), style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );

    if (compact) {
      return Row(children: [playButton, const SizedBox(width: 4), Expanded(child: slider)]);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            StreamBuilder<double>(
              stream: player.speedStream,
              builder: (context, snap) {
                final speed = snap.data ?? 1.0;
                return ActionChip(
                  label: Text('${speed.toStringAsFixed(speed * 10 % 1 == 0 ? 1 : 2)}x'),
                  onPressed: () {
                    final i = speeds.indexWhere((s) => (s - speed).abs() < 0.01);
                    player.setSpeed(speeds[(i + 1) % speeds.length]);
                  },
                );
              },
            ),
            IconButton(
              tooltip: 'Atrás 10 s',
              iconSize: 30,
              icon: const Icon(Icons.replay_10),
              onPressed: () => _skip(-10000),
            ),
            playButton,
            IconButton(
              tooltip: 'Adelante 10 s',
              iconSize: 30,
              icon: const Icon(Icons.forward_10),
              onPressed: () => _skip(10000),
            ),
            const SizedBox(width: 48),
          ],
        ),
        slider,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isCurrent ? highlight : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: onSpeakerTap,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${speaker?.name ?? 'Hablante 1'} '),
                      const WidgetSpan(child: Icon(Icons.edit_outlined, size: 15)),
                    ]),
                    style: muted?.copyWith(fontSize: 15),
                  ),
                ),
                const SizedBox(width: 10),
                Text(formatMs(segment.startMs), style: muted?.copyWith(fontSize: 15)),
                if (isImportant) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.star, size: 14, color: Colors.amber),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(segment.text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 19, height: 1.35)),
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

/// Transcribe (o vuelve a transcribir) una grabación ya guardada.
class TranscribeNowButton extends ConsumerStatefulWidget {
  const TranscribeNowButton({super.key, required this.blockId, required this.audioPath});
  final String blockId;
  final String audioPath;

  @override
  ConsumerState<TranscribeNowButton> createState() => _TranscribeNowButtonState();
}

class _TranscribeNowButtonState extends ConsumerState<TranscribeNowButton> {
  String? _status;
  String? _error;

  Future<void> _run() async {
    final service = ref.read(transcriptionServiceProvider);
    setState(() {
      _error = null;
      _status = 'Preparando…';
    });
    try {
      if (!await service.isModelReady()) {
        await service.ensureModel(
          onProgress: (p) {
            if (mounted) setState(() => _status = 'Descargando el modelo de voz (solo la primera vez)… $p%');
          },
        );
      }
      if (mounted) setState(() => _status = 'Transcribiendo…');
      final raw = await service.transcribeFile(
        widget.audioPath,
        lang: ref.read(settingsProvider).language,
        onProgress: (p) {
          if (mounted) setState(() => _status = 'Transcribiendo… $p%');
        },
      );
      if (raw.isEmpty) {
        throw TranscriptionException('No se escuchó voz en esta grabación.');
      }
      await ref
          .read(notesRepositoryProvider)
          .replaceSegments(widget.blockId, const SegmentMerger().merge(raw, const []));
      if (mounted) setState(() => _status = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = null;
          _error = e is TranscriptionException ? e.message : 'No se pudo transcribir: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status != null) {
      return Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(child: Text(_status!)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        FilledButton.icon(
          onPressed: _run,
          icon: const Icon(Icons.subtitles_outlined),
          label: const Text('Transcribir ahora'),
        ),
      ],
    );
  }
}
