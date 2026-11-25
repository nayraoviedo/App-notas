import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
import '../../notes/presentation/widgets/audio_block_view.dart' show askName;
import '../../speakers/domain/speaker.dart';
import '../../speakers/presentation/speaker_change_banner.dart';
import '../application/recording_controller.dart';

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordingControllerProvider);
    final controller = ref.read(recordingControllerProvider.notifier);
    final speakers = ref.watch(speakersProvider).valueOrNull ?? const <Speaker>[];

    ref.listen(recordingControllerProvider, (prev, next) {
      if (next.status == RecordingStatus.done) {
        if (next.message != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(next.message!)));
        }
        context.go('/notes/${widget.noteId}');
      }
      if (prev?.liveText != next.liveText && _scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });

    final processing = state.status == RecordingStatus.processing;
    final currentName =
        speakers.where((s) => s.id == state.currentSpeakerId).firstOrNull?.name;

    return PopScope(
      canPop: !state.isActive && !processing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || processing) return;
        final discard = await _confirmDiscard();
        if (discard == true) {
          await controller.cancel();
          if (mounted) context.go('/notes/${widget.noteId}');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(formatMs(state.elapsedMs)),
          actions: [
            if (state.isActive)
              TextButton.icon(
                icon: const Icon(Icons.record_voice_over_outlined),
                label: Text(currentName ?? '¿Quién habla?'),
                onPressed: () => _chooseCurrentSpeaker(speakers),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (state.message != null && !processing)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(state.message!,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              Expanded(
                child: processing
                    ? _Processing(progress: state.progress)
                    : SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          state.liveText.isEmpty ? 'Escuchando…' : state.liveText,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
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
              if (state.markersMs.isNotEmpty || state.photos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '⭐ ${state.markersMs.length}   📷 ${state.photos.length}',
                  ),
                ),
              if (!processing) _Controls(state: state, controller: controller),
            ],
          ),
        ),
      ),
    );
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

class _Controls extends StatelessWidget {
  const _Controls({required this.state, required this.controller});
  final RecordingState state;
  final RecordingController controller;

  @override
  Widget build(BuildContext context) {
    final paused = state.status == RecordingStatus.paused;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            icon: Icons.star_border,
            label: 'Importante',
            onPressed: state.isActive ? controller.addMarker : null,
          ),
          _RoundButton(
            icon: Icons.photo_camera_outlined,
            label: 'Foto',
            onPressed: state.isActive ? controller.takePhoto : null,
          ),
          _RoundButton(
            icon: paused ? Icons.play_arrow : Icons.pause,
            label: paused ? 'Seguir' : 'Pausa',
            onPressed: !state.isActive
                ? null
                : (paused ? controller.resume : controller.pause),
          ),
          _RoundButton(
            icon: Icons.stop,
            label: 'Terminar',
            color: Colors.red,
            onPressed: state.isActive ? controller.stop : null,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            iconSize: 30,
            onPressed: onPressed,
            icon: Icon(icon, color: color),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}

class _Processing extends StatelessWidget {
  const _Processing({required this.progress});
  final int progress;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(value: progress == 0 ? null : progress / 100),
              const SizedBox(height: 16),
              const Text('Transcribiendo y ordenando por párrafos…'),
            ],
          ),
        ),
      );
}
