import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../camera/in_app_camera_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
import '../../notes/presentation/widgets/audio_block_view.dart' show askName;
import '../../settings/settings.dart';
import '../../speakers/domain/speaker.dart';
import '../../speakers/presentation/speaker_change_banner.dart';
import '../application/recording_controller.dart';
import '../../../core/widgets/doodle_icon.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key, required this.noteId});
  final String noteId;

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(recordingControllerProvider.notifier).start(widget.noteId),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _leftToDetail = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordingControllerProvider);
    final controller = ref.read(recordingControllerProvider.notifier);
    final speakers = ref.watch(speakersProvider).valueOrNull ?? const <Speaker>[];
    final note = ref.watch(noteProvider(widget.noteId)).valueOrNull;
    final cloud = ref.watch(_hasGroqProvider).valueOrNull ?? false;

    ref.listen(recordingControllerProvider, (prev, next) {
      // Apenas se guarda el audio, se abre la grabación (transcripción y
      // resumen); la transcripción sigue allí.
      if (!_leftToDetail && next.savedBlockId != null && prev?.savedBlockId != next.savedBlockId) {
        _leftToDetail = true;
        context.pushReplacement('/notes/${widget.noteId}/audio/${next.savedBlockId}');
        return;
      }
      if (next.status == RecordingStatus.done && !_leftToDetail) {
        if (next.message != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message!)));
        }
        context.pop();
      }
      if (prev?.liveText != next.liveText && _scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });

    final processing = state.status == RecordingStatus.processing;
    final currentName = speakers.where((s) => s.id == state.currentSpeakerId).firstOrNull?.name;
    final created = note?.createdAt ?? DateTime.now();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return PopScope(
      canPop: !state.isActive && !processing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || processing) return;
        // Atrás = minimizar: la grabación sigue (aparece arriba en la hoja).
        if (state.isActive && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEAF3FF), Color(0xFFFFF9EE)],
              stops: [0, 0.35],
            ),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Arriba: opciones y minimizar.
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Opciones',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: state.isActive ? () => _options(speakers) : null,
                    ),
                    IconButton(
                      tooltip: 'Minimizar (sigue grabando)',
                      icon: const Icon(Icons.close_fullscreen),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: GestureDetector(
                    onTap: note == null ? null : () => _rename(note.title),
                    child: Text(
                      note?.displayTitle ?? 'Grabación',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700, height: 1.15),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
                  child: Row(
                    children: [
                      Text(_when(created), style: TextStyle(color: muted, fontSize: 16)),
                      const Spacer(),
                      _Chip(
                        icon: Icons.auto_awesome,
                        text: cloud ? 'Transcripción avanzada' : 'Transcripción en el teléfono',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                if (state.status == RecordingStatus.error)
                  _MicPermissionHelp(
                    message: state.message ?? '',
                    blocked: state.micBlocked,
                    onRetry: () => controller.start(widget.noteId),
                  ),
                Expanded(
                  child: processing
                      ? _Processing(progress: state.progress, label: state.progressLabel)
                      : _LiveTranscript(
                          state: state,
                          scroll: _scroll,
                          speaker: currentName ?? 'Hablante 1',
                          cloud: cloud,
                          onSpeaker: () => _chooseCurrentSpeaker(speakers),
                        ),
                ),
                if (state.pendingSpeakerChange != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SpeakerChangeBanner(
                      suggestion: state.pendingSpeakerChange!,
                      speakers: speakers,
                      onPick: controller.confirmSpeaker,
                      onDismiss: controller.dismissSpeakerChange,
                      onNew: () async {
                        final name = await askName(context);
                        if (name != null) await controller.confirmNewSpeaker(name);
                      },
                    ),
                  ),
                if (!processing && state.status != RecordingStatus.error) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 34,
                            child: CustomPaint(
                              painter: _WavePainter(state.levels, Theme.of(context).colorScheme.primary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(_hms(state.elapsedMs),
                            style: TextStyle(fontSize: 20, color: muted, fontFeatures: const [FontFeature.tabularFigures()])),
                      ],
                    ),
                  ),
                  _BottomBar(state: state, controller: controller, onQuickNote: () => _quickNote(state)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _hms(int ms) {
    final s = ms ~/ 1000;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(s ~/ 3600)}:${two(s ~/ 60 % 60)}:${two(s % 60)}';
  }

  static String _when(DateTime d) {
    final now = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Hoy $hm';
    return '${d.day}/${d.month}/${d.year} $hm';
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

  /// La nota queda en el minuto en que se tocó el botón, no al guardarla.
  Future<void> _quickNote(RecordingState state) async {
    final atMs = state.elapsedMs;
    final c = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: c,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Nota rápida en ${formatMs(atMs)}…',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.check), onPressed: () => Navigator.pop(context, c.text)),
          ],
        ),
      ),
    );
    if (text != null) ref.read(recordingControllerProvider.notifier).addQuickNote(text, atMs: atMs);
  }

  /// Engranaje: quién habla, marcar importante y foto.
  Future<void> _options(List<Speaker> speakers) async {
    final controller = ref.read(recordingControllerProvider.notifier);
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.record_voice_over_outlined),
              title: const Text('¿Quién está hablando?'),
              onTap: () => Navigator.pop(context, 'speaker'),
            ),
            ListTile(
              leading: const Icon(Icons.star_border),
              title: const Text('Marcar este momento como importante'),
              onTap: () => Navigator.pop(context, 'star'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto (pizarra, diapositiva…)'),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Descartar grabación'),
              onTap: () => Navigator.pop(context, 'discard'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (a) {
      case 'speaker':
        await _chooseCurrentSpeaker(speakers);
      case 'star':
        controller.addMarker();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: DoodleText('⭐ Marcado')));
      case 'photo':
        await controller.takePhoto(() => captureWithInAppCamera(context));
      case 'discard':
        if (await _confirmDiscard() == true) {
          await controller.cancel();
          if (mounted) context.pop();
        }
    }
  }

  Future<bool?> _confirmDiscard() => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Descartar la grabación?'),
          content: const Text('Para guardarla, usa el botón de detener.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Seguir grabando')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Descartar')),
          ],
        ),
      );

  Future<void> _chooseCurrentSpeaker(List<Speaker> speakers) async {
    final controller = ref.read(recordingControllerProvider.notifier);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('¿Quién está hablando ahora?')),
            for (final s in speakers)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(s.name),
                onTap: () => Navigator.pop(context, s.id),
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
    if (choice == null) return;
    var id = choice;
    if (choice == '__new__') {
      if (!mounted) return;
      final name = await askName(context);
      if (name == null) return;
      id = await ref.read(speakersRepositoryProvider).create(name);
    }
    controller.setCurrentSpeaker(id);
  }
}

/// ¿Hay clave de Groq? (transcripción "avanzada" en la nube).
final _hasGroqProvider = FutureProvider.autoDispose<bool>(
    (ref) async => ((await ref.read(apiKeysProvider).read(AiProvider.groq)) ?? '').trim().isNotEmpty);

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: c, fontSize: 13.5)),
        ],
      ),
    );
  }
}

/// Texto en vivo en párrafos "00:00 Hablante 1 ✎", y las notas rápidas.
class _LiveTranscript extends StatelessWidget {
  const _LiveTranscript({
    required this.state,
    required this.scroll,
    required this.speaker,
    required this.cloud,
    required this.onSpeaker,
  });
  final RecordingState state;
  final ScrollController scroll;
  final String speaker;
  final bool cloud;
  final VoidCallback onSpeaker;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final text = state.liveText.trim();
    // Párrafos por oración (el texto en vivo llega todo junto).
    final parts = text.isEmpty
        ? const <String>[]
        : text.split(RegExp(r'(?<=[.!?¿¡])\s+')).where((p) => p.trim().isNotEmpty).toList();
    final total = parts.fold<int>(0, (a, p) => a + p.length);
    var acc = 0;
    final notes = state.markers.where((m) => m.isQuickNote).toList();
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        if (parts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              children: [
                Icon(Icons.graphic_eq, size: 40, color: muted),
                const SizedBox(height: 8),
                DoodleText(
                  state.status == RecordingStatus.paused
                      ? 'En pausa'
                      : cloud
                          ? 'Escuchando… 🎧\nLa transcripción avanzada aparece al terminar.'
                          : 'Escuchando… 🎧',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 17),
                ),
              ],
            ),
          ),
        for (final (i, p) in parts.indexed) ...[
          () {
            // Minuto aproximado de cada párrafo (proporcional al texto).
            final at = total == 0 ? 0 : (state.elapsedMs * acc / total).round();
            acc += p.length;
            return Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: GestureDetector(
                onTap: onSpeaker,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${formatMs(at)}  $speaker '),
                    const WidgetSpan(child: Icon(Icons.edit_outlined, size: 16)),
                  ]),
                  style: TextStyle(color: muted, fontSize: 16),
                ),
              ),
            );
          }(),
          Text(p.trim(),
              style: TextStyle(
                fontSize: 21,
                height: 1.35,
                color: i == parts.length - 1
                    ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)
                    : Theme.of(context).colorScheme.onSurface,
              )),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 18),
          for (final m in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: DoodleText('📝 ${formatMs(m.atMs)}  ${m.label}', style: TextStyle(color: muted)),
            ),
        ],
        if (state.photos.isNotEmpty || state.markers.any((m) => !m.isQuickNote))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DoodleText(
              '⭐ ${state.markers.where((m) => !m.isQuickNote).length}   📷 ${state.photos.length}',
              style: TextStyle(color: muted),
            ),
          ),
      ],
    );
  }
}

/// Onda de sonido: barritas con el volumen reciente.
class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.color);
  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 64;
    final step = size.width / n;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.5, step * 0.45);
    final start = n - levels.length;
    for (var i = 0; i < n; i++) {
      final x = i * step + step / 2;
      final v = i >= start ? levels[i - start] : 0.0;
      final h = math.max(3.0, v * size.height);
      paint.color = i >= start ? color : color.withValues(alpha: 0.25);
      canvas.drawLine(Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.levels != levels;
}

/// Abajo: "Notas rápidas", pausa y detener (cuadrado rojo).
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state, required this.controller, required this.onQuickNote});
  final RecordingState state;
  final RecordingController controller;
  final VoidCallback onQuickNote;

  @override
  Widget build(BuildContext context) {
    final paused = state.status == RecordingStatus.paused;
    final bg = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        children: [
          Material(
            color: bg,
            borderRadius: BorderRadius.circular(30),
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: state.isActive ? onQuickNote : null,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.draw_outlined),
                    SizedBox(width: 8),
                    Text('Notas rápidas', style: TextStyle(fontSize: 17)),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          _Pill(
            color: bg,
            onTap: !state.isActive ? null : (paused ? controller.resume : controller.pause),
            child: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 32),
          ),
          const SizedBox(width: 14),
          _Pill(
            color: bg,
            onTap: state.isActive ? controller.stop : null,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: const Color(0xFFE5252A), borderRadius: BorderRadius.circular(5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.onTap, required this.child});
  final Color color;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: SizedBox(width: 76, height: 54, child: Center(child: child)),
        ),
      );
}

class _Processing extends StatelessWidget {
  const _Processing({required this.progress, this.label});
  final int progress;
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(value: progress == 0 ? null : progress / 100),
              const SizedBox(height: 16),
              Text(label ?? 'Transcribiendo y ordenando por párrafos…', textAlign: TextAlign.center),
              if (progress > 0) Text('$progress%'),
            ],
          ),
        ),
      );
}

/// Ayuda cuando falta el permiso del micrófono: volver a pedirlo o abrir
/// los ajustes de la app.
class _MicPermissionHelp extends StatelessWidget {
  const _MicPermissionHelp({
    required this.message,
    required this.blocked,
    required this.onRetry,
  });

  final String message;
  final bool blocked;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.mic_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.mic),
                  label: const Text('Dar permiso'),
                  onPressed: onRetry,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Abrir ajustes'),
                  onPressed: () => openAppSettings(),
                ),
              ],
            ),
            if (blocked)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Después de activarlo, vuelve aquí y toca "Dar permiso".',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      );
}
