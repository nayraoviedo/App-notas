import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Temporizador de estudio (por ejemplo, 25 min tipo Pomodoro). Es global:
/// sigue corriendo aunque cambies de nota o de hoja.
class StudyTimerState {
  const StudyTimerState({this.endsAt, this.total = Duration.zero, this.finished = false});
  final DateTime? endsAt;
  final Duration total;
  final bool finished;

  bool get running => endsAt != null;
  Duration get remaining {
    final e = endsAt;
    if (e == null) return Duration.zero;
    final r = e.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }
}

class StudyTimerController extends Notifier<StudyTimerState> {
  Timer? _timer;

  @override
  StudyTimerState build() {
    ref.onDispose(() => _timer?.cancel());
    return const StudyTimerState();
  }

  void start(Duration d) {
    _timer?.cancel();
    state = StudyTimerState(endsAt: DateTime.now().add(d), total: d);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.remaining == Duration.zero) {
        _timer?.cancel();
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        state = StudyTimerState(total: state.total, finished: true);
      } else {
        // Notificar cada segundo para que el contador se actualice.
        state = StudyTimerState(endsAt: state.endsAt, total: state.total);
      }
    });
  }

  void stop() {
    _timer?.cancel();
    state = const StudyTimerState();
  }
}

final studyTimerProvider =
    NotifierProvider<StudyTimerController, StudyTimerState>(StudyTimerController.new);

/// Botón para la barra superior: muestra el tiempo restante o un reloj.
class StudyTimerButton extends ConsumerWidget {
  const StudyTimerButton({super.key});

  static const _options = [5, 10, 15, 25, 45, 60];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(studyTimerProvider);

    ref.listen(studyTimerProvider, (prev, next) {
      if (next.finished && !(prev?.finished ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⏰ ¡Tiempo! Toma un descanso.')),
        );
      }
    });

    if (!t.running) {
      return IconButton(
        tooltip: 'Temporizador',
        icon: const Icon(Icons.timer_outlined),
        onPressed: () => _choose(context, ref),
      );
    }
    final r = t.remaining;
    final label = '${r.inMinutes}:${(r.inSeconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        avatar: const Icon(Icons.timer, size: 16),
        label: Text(label),
        onPressed: () => _running(context, ref),
      ),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Temporizador', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in _options)
                    ActionChip(
                      label: Text('$m min'),
                      onPressed: () => Navigator.pop(context, m),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (minutes != null) {
      ref.read(studyTimerProvider.notifier).start(Duration(minutes: minutes));
    }
  }

  Future<void> _running(BuildContext context, WidgetRef ref) async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Temporizador'),
        content: const Text('¿Detener el temporizador?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true), child: const Text('Detener')),
        ],
      ),
    );
    if (stop == true) ref.read(studyTimerProvider.notifier).stop();
  }
}
