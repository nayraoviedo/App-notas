import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
import '../../notes/domain/note_block.dart';
import '../../notes/presentation/widgets/audio_block_view.dart';
import '../../settings/settings.dart';
import '../application/audio_tools.dart';
import '../application/recording_controller.dart';
import '../../summary/application/summary_runner.dart';
import '../../summary/domain/summary.dart';
import '../../drawing/presentation/widgets/canvas_item_view.dart' show measureTextItem;
import '../../study/domain/cornell.dart';
import 'package:go_router/go_router.dart';

/// Vista completa de una grabación, con tres pestañas:
/// Transcripción · Notas rápidas · Resumen, y el reproductor abajo.
class RecordingDetailScreen extends ConsumerStatefulWidget {
  const RecordingDetailScreen({super.key, required this.noteId, required this.blockId});
  final String noteId;
  final String blockId;

  @override
  ConsumerState<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends ConsumerState<RecordingDetailScreen> {
  final _player = AudioPlayer();
  String? _loadedPath;
  bool _onlyImportant = false;

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
    final note = ref.watch(noteProvider(widget.noteId)).valueOrNull;
    final blocks = ref.watch(blocksProvider(widget.noteId)).valueOrNull ?? const [];
    final audio = blocks.whereType<AudioBlock>().where((b) => b.id == widget.blockId).firstOrNull;
    final photos = blocks
        .whereType<ImageBlock>()
        .where((b) => b.anchor?.audioBlockId == widget.blockId)
        .toList();
    final lang = ref.watch(settingsProvider).language;

    if (audio != null && _loadedPath != audio.path) {
      _loadedPath = audio.path;
      _player.setFilePath(audio.path);
    }

    final rec = ref.watch(recordingControllerProvider);
    final busy = rec.status == RecordingStatus.processing && rec.savedBlockId == widget.blockId;
    final cloud = ref.watch(_groqProvider).valueOrNull ?? false;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final created = note?.createdAt ?? DateTime.now();
    final now = DateTime.now();
    final hm = '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    final when = created.year == now.year && created.month == now.month && created.day == now.day
        ? 'Hoy $hm'
        : '${created.day}/${created.month}/${created.year} $hm';

    // Avisar el resultado de la transcripción (también si falló).
    ref.listen(recordingControllerProvider, (prev, next) {
      if (prev?.status == RecordingStatus.processing &&
          next.status == RecordingStatus.done &&
          next.savedBlockId == widget.blockId) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(next.message ?? 'Transcripción lista ✓'),
        ));
      }
    });

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            if (audio != null)
              PopupMenuButton<AudioExport>(
                tooltip: 'Exportar',
                icon: const Icon(Icons.ios_share),
                onSelected: (what) async {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(const SnackBar(content: Text('Preparando…')));
                  try {
                    await shareRecording(ref, audio, title: note?.displayTitle ?? '', what: what);
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: AudioExport.audio,
                    child: ListTile(leading: Icon(Icons.graphic_eq), title: Text('Audio (m4a)')),
                  ),
                  PopupMenuItem(
                    value: AudioExport.transcript,
                    child: ListTile(leading: Icon(Icons.subject), title: Text('Transcripción (.txt)')),
                  ),
                  PopupMenuItem(
                    value: AudioExport.summary,
                    child: ListTile(leading: Icon(Icons.auto_awesome), title: Text('Resumen (.txt)')),
                  ),
                  PopupMenuItem(
                    value: AudioExport.all,
                    child: ListTile(leading: Icon(Icons.folder_zip_outlined), title: Text('Todo junto')),
                  ),
                ],
              ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
              child: GestureDetector(
                onTap: note == null ? null : () => _rename(note.title),
                child: Text(note?.displayTitle ?? '',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700, height: 1.15)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(when, style: TextStyle(color: muted, fontSize: 16)),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _Tag(text: switch (lang) {
                    'es' => 'Español',
                    'en' => 'Inglés',
                    'auto' => 'Idioma automático',
                    _ => lang.toUpperCase(),
                  }, color: const Color(0xFF6C5CE7)),
                  _Tag(
                    icon: Icons.auto_awesome,
                    text: cloud ? 'Transcripción avanzada' : 'En el teléfono',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  _Tag(icon: Icons.schedule, text: formatMs(audio?.durationMs ?? 0), color: muted),
                  IconButton(
                    tooltip: 'Solo lo importante ⭐',
                    isSelected: _onlyImportant,
                    icon: const Icon(Icons.star_border),
                    selectedIcon: const Icon(Icons.star, color: Colors.amber),
                    onPressed: () => setState(() => _onlyImportant = !_onlyImportant),
                  ),
                ],
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Transcripción'),
                Tab(text: 'Notas rápidas'),
                Tab(text: 'Resumen'),
              ],
            ),
            if (busy)
              Material(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, value: rec.progress == 0 ? null : rec.progress / 100),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          (rec.progressLabel ?? 'Transcribiendo…').replaceAll('Audio guardado ✔\n', ''),
                        ),
                      ),
                      if (rec.progress > 0) Text('${rec.progress}%'),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: audio == null
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        TranscriptView(
                          blockId: widget.blockId,
                          audioPath: audio.path,
                          player: _player,
                          photos: photos,
                          onlyImportant: _onlyImportant,
                        ),
                        _QuickNotesTab(blockId: widget.blockId, player: _player, onSeek: _seek),
                        _SummaryTab(noteId: widget.noteId, blockId: widget.blockId, onSeek: _seek),
                      ],
                    ),
            ),
          ],
        ),
        bottomNavigationBar: audio == null
            ? null
            : Material(
                elevation: 8,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: PlayerBar(player: _player, durationMs: audio.durationMs),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _rename(String current) async {
    final c = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Título de la grabación'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    if (v != null) await ref.read(notesRepositoryProvider).renameNote(widget.noteId, v);
  }
}

final _groqProvider = FutureProvider.autoDispose<bool>(
    (ref) async => ((await ref.read(apiKeysProvider).read(AiProvider.groq)) ?? '').trim().isNotEmpty);

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 4)],
              Text(text, style: TextStyle(color: color, fontSize: 14)),
            ],
          ),
        ),
      );
}

// ------------------------------------------------------------ Notas rápidas

class _QuickNotesTab extends ConsumerStatefulWidget {
  const _QuickNotesTab({required this.blockId, required this.player, required this.onSeek});
  final String blockId;
  final AudioPlayer player;
  final Future<void> Function(int ms) onSeek;

  @override
  ConsumerState<_QuickNotesTab> createState() => _QuickNotesTabState();
}

class _QuickNotesTabState extends ConsumerState<_QuickNotesTab> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  int? _atMs;

  @override
  void initState() {
    super.initState();
    // La nota queda en el minuto en que empezaste a escribir.
    _focus.addListener(() {
      if (_focus.hasFocus) _atMs = widget.player.position.inMilliseconds;
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    await ref.read(notesRepositoryProvider).addMarker(
          widget.blockId,
          _atMs ?? widget.player.position.inMilliseconds,
          label: t,
        );
    _text.clear();
    _atMs = null;
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final markers = ref.watch(markersProvider(widget.blockId)).valueOrNull ?? const [];
    final repo = ref.read(notesRepositoryProvider);

    return Column(
      children: [
        Expanded(
          child: markers.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aquí aparecen las notas rápidas y las marcas ⭐ que hiciste al '
                      'grabar. También puedes agregar más mientras escuchas.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: markers.length,
                  itemBuilder: (context, i) {
                    final m = markers[i];
                    return ListTile(
                      leading: ActionChip(
                        avatar: const Icon(Icons.play_arrow, size: 16),
                        label: Text(formatMs(m.atMs)),
                        onPressed: () => widget.onSeek(m.atMs),
                      ),
                      title: Text(m.isQuickNote ? m.label! : '⭐ Momento importante'),
                      onTap: () => widget.onSeek(m.atMs),
                      trailing: PopupMenuButton<String>(
                        onSelected: (a) async {
                          if (a == 'delete' && m.id != null) {
                            await repo.deleteMarker(m.id!);
                          } else if (a == 'edit' && m.id != null) {
                            final c = TextEditingController(text: m.label ?? '');
                            final v = await showDialog<String>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('Nota en ${formatMs(m.atMs)}'),
                                content: TextField(controller: c, autofocus: true, maxLines: null),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancelar')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(context, c.text.trim()),
                                      child: const Text('Guardar')),
                                ],
                              ),
                            );
                            if (v != null && v.isNotEmpty) await repo.updateMarker(m.id!, v);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Editar')),
                          PopupMenuItem(value: 'delete', child: Text('Borrar')),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 3,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    hintText: 'Nota rápida en este minuto…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.send), onPressed: _add),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Resumen

class _SummaryTab extends ConsumerStatefulWidget {
  const _SummaryTab({required this.noteId, required this.blockId, required this.onSeek});
  final String noteId;
  final String blockId;
  final Future<void> Function(int ms) onSeek;

  @override
  ConsumerState<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends ConsumerState<_SummaryTab> {
  bool _byChapters = false;
  String? _status;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _status = 'Preparando…';
      _error = null;
    });
    try {
      await generateSummary(ref, widget.blockId,
          onStatus: (s) {
        if (mounted) setState(() => _status = s);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _status = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(summaryProvider(widget.blockId)).valueOrNull;
    final text = Theme.of(context).textTheme;

    if (_status != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(_status!),
          ],
        ),
      );
    }

    if (summary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, size: 40),
              const SizedBox(height: 12),
              const Text(
                'Genera un resumen completo y por capítulos, con puntos clave y '
                'tareas mencionadas.',
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generar resumen'),
                onPressed: _generate,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            ChoiceChip(
              label: const Text('Resumen completo'),
              selected: !_byChapters,
              onSelected: (_) => setState(() => _byChapters = false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Por capítulos'),
              selected: _byChapters,
              onSelected: (_) => setState(() => _byChapters = true),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Pasar a hoja Cornell',
              icon: const Icon(Icons.view_sidebar_outlined),
              onPressed: () => _toCornell(summary),
            ),
            IconButton(
              tooltip: 'Crear tarjetas de repaso',
              icon: const Icon(Icons.style_outlined),
              onPressed: () => _toFlashcards(summary),
            ),
            IconButton(
              tooltip: 'Copiar',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _asText(summary)));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Resumen copiado')));
              },
            ),
            IconButton(
              tooltip: 'Volver a generar',
              icon: const Icon(Icons.refresh),
              onPressed: _generate,
            ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        Text(summary.title, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (!_byChapters) ...[
          Text(summary.overview, style: text.bodyLarge),
          if (summary.keyPoints.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Puntos clave', style: text.titleMedium),
            const SizedBox(height: 6),
            for (final k in summary.keyPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [const Text('•  '), Expanded(child: Text(k))],
                ),
              ),
          ],
          if (summary.tasks.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Tareas y fechas', style: text.titleMedium),
            for (final t in summary.tasks)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: false,
                onChanged: (_) {},
                title: Text(t.task),
                subtitle: t.due == null ? null : Text(t.due!),
              ),
          ],
        ] else
          for (final c in summary.chapters)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.play_arrow, size: 16),
                    label: Text(formatMs(c.atMs)),
                    onPressed: () => widget.onSeek(c.atMs),
                  ),
                  const SizedBox(height: 4),
                  Text(c.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(c.summary, style: text.bodyLarge),
                ],
              ),
            ),
        const SizedBox(height: 12),
        Text('Generado con ${summary.provider}', style: text.bodySmall),
      ],
    );
  }

  /// El resumen pasa a una (o varias) hojas Cornell dentro de la nota.
  Future<void> _toCornell(TranscriptSummary s) async {
    final pages = cornellPages(s, measure: measureTextItem);
    final storage = ref.read(fileStorageProvider);
    String? first;
    for (final page in pages) {
      final path = await storage.newDrawingPath();
      await ref.read(drawingStoreProvider).save(path, page);
      await ref.read(notesRepositoryProvider).addDrawingBlock(widget.noteId, path);
      first ??= path;
    }
    if (!mounted || first == null) return;
    context.push('/notes/${widget.noteId}/drawing', extra: first);
  }

  /// Una tarjeta por capítulo (o por punto clave).
  Future<void> _toFlashcards(TranscriptSummary s) async {
    final repo = ref.read(flashcardsRepositoryProvider);
    final pairs = s.chapters.isNotEmpty
        ? [for (final c in s.chapters) (c.title, c.summary)]
        : [for (final k in s.keyPoints) ('¿Qué recuerdas de: ${k.split(' ').take(6).join(' ')}…?', k)];
    for (final (f, b) in pairs) {
      await repo.add(front: f, back: b, noteId: widget.noteId);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${pairs.length} tarjetas creadas en Estudio'),
      action: SnackBarAction(label: 'Repasar', onPressed: () => context.push('/study')),
    ));
  }

  static String _asText(TranscriptSummary s) {
    final b = StringBuffer()
      ..writeln(s.title)
      ..writeln()
      ..writeln(s.overview);
    if (s.keyPoints.isNotEmpty) {
      b.writeln('\nPuntos clave:');
      for (final k in s.keyPoints) {
        b.writeln('• $k');
      }
    }
    if (s.chapters.isNotEmpty) {
      b.writeln('\nCapítulos:');
      for (final c in s.chapters) {
        b.writeln('[${formatMs(c.atMs)}] ${c.title}\n${c.summary}\n');
      }
    }
    return b.toString();
  }
}
