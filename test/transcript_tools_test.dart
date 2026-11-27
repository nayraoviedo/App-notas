import 'dart:ui';

import 'package:app_notas/features/drawing/domain/canvas_item.dart';
import 'package:app_notas/features/recording/application/transcript_tools.dart';
import 'package:app_notas/features/transcription/data/groq_transcription.dart';
import 'package:app_notas/features/transcription/domain/transcript_segment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('párrafos por hablante y hojas rayadas que continúan', () {
    final segs = [
      const TranscriptSegment(startMs: 0, endMs: 1000, text: 'Hola', speakerId: 'a'),
      const TranscriptSegment(startMs: 1000, endMs: 2000, text: 'a todos.', speakerId: 'a'),
      const TranscriptSegment(startMs: 2000, endMs: 3000, text: 'Gracias', speakerId: 'b'),
    ];
    final p = transcriptParagraphs(segs);
    expect(p.length, 2);
    expect(p.first.$3, 'Hola a todos.');

    Size measure(TextItem t) => Size(t.width, ((t.text.length / 40).ceil().clamp(1, 999)) * 40.0);
    final long = [for (var i = 0; i < 40; i++) (i * 60000, 'Profe', 'Palabra ' * 60)];
    final pages = transcriptPages('Clase', long, measure: measure);
    expect(pages.length, greaterThan(3));
    for (final pg in pages) {
      for (final t in pg.layers.first.items.whereType<TextItem>()) {
        expect(t.y, lessThan(pg.height));
      }
    }
  });

  test('lee la transcripción de Gemini (MM:SS y entre ```)', () {
    final segs = parseGeminiSegments('''```json
{"segments":[{"start":"00:05","text":"Hola clase."},{"start":"01:02.5","end":"01:10","text":"Hoy vemos mitosis."}]}
```''');
    expect(segs.length, 2);
    expect(segs.first.startMs, 5000);
    expect(segs.first.endMs, 62500); // termina donde empieza el siguiente
    expect(segs.last.endMs, 70000);
    expect(parseGeminiSegments('texto suelto').single.text, 'texto suelto');
  });
}
