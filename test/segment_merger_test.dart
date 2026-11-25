import 'package:app_notas/features/speakers/domain/speaker.dart';
import 'package:app_notas/features/transcription/application/segment_merger.dart';
import 'package:app_notas/features/transcription/domain/transcript_segment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const merger = SegmentMerger();

  TranscriptSegment seg(int s, int e, String t) =>
      TranscriptSegment(startMs: s, endMs: e, text: t);

  test('une fragmentos cortos de la misma persona en un párrafo', () {
    final out = merger.merge(
      [seg(0, 4000, 'no vamos a poder'), seg(4200, 8000, 'desarrollar más rápido')],
      const [],
    );
    expect(out, hasLength(1));
    expect(out.single.text, 'no vamos a poder desarrollar más rápido');
    expect(out.single.endMs, 8000);
  });

  test('separa cuando cambia la persona', () {
    final out = merger.merge(
      [seg(0, 4000, 'hola'), seg(4200, 8000, 'qué tal')],
      const [
        SpeakerTurn(atMs: 0, speakerId: 'ana'),
        SpeakerTurn(atMs: 4100, speakerId: 'luis'),
      ],
    );
    expect(out.map((s) => s.speakerId), ['ana', 'luis']);
  });

  test('separa cuando hay una pausa larga', () {
    final out = merger.merge(
      [seg(0, 2000, 'uno'), seg(6000, 8000, 'dos')],
      const [],
    );
    expect(out, hasLength(2));
  });
}
