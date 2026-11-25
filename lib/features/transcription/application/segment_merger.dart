import '../../speakers/domain/speaker.dart';
import '../domain/transcript_segment.dart';

/// Convierte los fragmentos cortos de Whisper en párrafos legibles.
///
/// 1. Asigna a cada fragmento la persona que hablaba en ese momento.
/// 2. Une fragmentos seguidos de la misma persona en un solo párrafo, salvo
///    que haya una pausa larga o el párrafo ya sea muy largo.
class SegmentMerger {
  const SegmentMerger({
    this.maxGapMs = 1500,
    this.maxParagraphChars = 500,
  });

  final int maxGapMs;
  final int maxParagraphChars;

  List<TranscriptSegment> merge(
    List<TranscriptSegment> raw,
    List<SpeakerTurn> turns,
  ) {
    final sortedTurns = [...turns]..sort((a, b) => a.atMs.compareTo(b.atMs));
    final withSpeakers = [
      for (final s in raw)
        s.copyWith(speakerId: speakerAt((s.startMs + s.endMs) ~/ 2, sortedTurns)),
    ];

    final out = <TranscriptSegment>[];
    for (final s in withSpeakers) {
      if (out.isEmpty) {
        out.add(s);
        continue;
      }
      final last = out.last;
      final sameSpeaker = last.speakerId == s.speakerId;
      final shortGap = s.startMs - last.endMs <= maxGapMs;
      final fits = last.text.length + s.text.length < maxParagraphChars;
      if (sameSpeaker && shortGap && fits) {
        out[out.length - 1] = TranscriptSegment(
          startMs: last.startMs,
          endMs: s.endMs,
          text: '${last.text} ${s.text}',
          speakerId: last.speakerId,
        );
      } else {
        out.add(s);
      }
    }
    return out;
  }

  /// Persona que hablaba en [ms] según los turnos confirmados.
  static String? speakerAt(int ms, List<SpeakerTurn> sortedTurns) {
    String? current;
    for (final t in sortedTurns) {
      if (t.atMs <= ms) {
        current = t.speakerId;
      } else {
        break;
      }
    }
    return current;
  }
}
