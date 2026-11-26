import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/drawing/presentation/painters/sticker_painter.dart' show catStickerAssets;
import '../../features/settings/settings.dart';
import '../daily_stats.dart';
import '../providers.dart';

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

  bool _rewardTaken = true;

  /// El premio de un pomodoro terminado se entrega una sola vez (aunque haya
  /// dos pantallas con el botón del temporizador).
  bool takeReward() {
    if (!state.finished || _rewardTaken) return false;
    _rewardTaken = true;
    return true;
  }

  void start(Duration d) {
    _timer?.cancel();
    _rewardTaken = false;
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
  static const _sleepyCat = 'assets/stickers/cat_06.png';

  /// Fin del pomodoro: un sticker de gatito de premio, que se guarda en "Míos".
  Future<void> _reward(BuildContext context, WidgetRef ref, Duration total) async {
    HapticFeedback.mediumImpact();
    final prefs = ref.read(sharedPreferencesProvider);
    final count = (prefs.getInt('pomodoro.count') ?? 0) + 1;
    await prefs.setInt('pomodoro.count', count);
    await DailyStats.bump(prefs, 'pomodoro');
    final asset = catStickerAssets[(DateTime.now().millisecondsSinceEpoch ~/ 1000) % catStickerAssets.length];
    try {
      final data = await rootBundle.load(asset);
      await ref.read(fileStorageProvider).saveBytes(data.buffer.asUint8List(), folder: 'stickers');
      ref.invalidate(customStickersProvider);
    } catch (_) {}
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¡Terminaste! 🎉', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(asset, width: 140, height: 140),
            const SizedBox(height: 8),
            Text('Ganaste este sticker (ya está en "Míos").\n'
                'Llevas $count ${count == 1 ? 'pomodoro' : 'pomodoros'}. Toma un descanso ☕',
                textAlign: TextAlign.center),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('¡Gracias!')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(studyTimerProvider);

    ref.listen(studyTimerProvider, (prev, next) {
      if (next.finished && !(prev?.finished ?? false)) {
        if (ref.read(studyTimerProvider.notifier).takeReward()) _reward(context, ref, next.total);
      }
    });

    if (!t.running) {
      return IconButton(
        tooltip: 'Pomodoro (temporizador de estudio)',
        icon: const Icon(Icons.timer_outlined),
        onPressed: () => _choose(context, ref),
      );
    }
    final r = t.remaining;
    final label = '${r.inMinutes}:${(r.inSeconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        // El gatito duerme mientras estudias.
        avatar: Image.asset(_sleepyCat, width: 22, height: 22),
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
              Row(
                children: [
                  Image.asset(_sleepyCat, width: 64, height: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Pomodoro con tu gatito: estudia mientras duerme y al terminar te regala un sticker 🎁',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
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
        title: const Text('Pomodoro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(_sleepyCat, width: 120, height: 120),
            const Text('Tu gatito duerme mientras estudias. Si lo detienes ahora, no hay sticker 🥺',
                textAlign: TextAlign.center),
          ],
        ),
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
