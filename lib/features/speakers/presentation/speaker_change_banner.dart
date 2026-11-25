import 'package:flutter/material.dart';

import '../domain/speaker.dart';

/// Aviso no intrusivo: "¿Habla otra persona?". Si nadie responde, la
/// grabación sigue igual.
class SpeakerChangeBanner extends StatelessWidget {
  const SpeakerChangeBanner({
    super.key,
    required this.suggestion,
    required this.speakers,
    required this.onPick,
    required this.onNew,
    required this.onDismiss,
  });

  final SpeakerChangeSuggestion suggestion;
  final List<Speaker> speakers;
  final void Function(String speakerId) onPick;
  final VoidCallback onNew;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final likely = speakers.where((s) => s.id == suggestion.likelySpeakerId).firstOrNull;
    final others = speakers.where((s) => s.id != suggestion.likelySpeakerId).take(4);

    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.record_voice_over_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    likely != null ? '¿Ahora habla ${likely.name}?' : '¿Habla otra persona?',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'No, es la misma',
                  icon: const Icon(Icons.close),
                  onPressed: onDismiss,
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (likely != null)
                  FilledButton.tonal(
                    onPressed: () => onPick(likely.id),
                    child: Text('Sí, ${likely.name}'),
                  ),
                for (final s in others)
                  ActionChip(label: Text(s.name), onPressed: () => onPick(s.id)),
                ActionChip(
                  avatar: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('Persona nueva'),
                  onPressed: onNew,
                ),
                TextButton(onPressed: onDismiss, child: const Text('No, la misma')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
