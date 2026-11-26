import 'dart:ui';

import 'package:app_notas/features/drawing/domain/drawing.dart';
import 'package:app_notas/features/study/domain/mind_map.dart';
import 'package:app_notas/features/summary/domain/summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mapa mental: centro, una rama por capítulo y su idea', () {
    const s = TranscriptSummary(
      title: 'La célula',
      overview: 'Clase sobre la célula.',
      chapters: [
        Chapter(atMs: 0, title: 'Membrana', summary: 'Controla lo que entra y sale. Es semipermeable.'),
        Chapter(atMs: 60000, title: 'Núcleo', summary: 'Guarda el ADN.'),
        Chapter(atMs: 120000, title: 'Mitocondria', summary: 'Produce energía para la célula.'),
      ],
    );
    final d = mindMapDrawing(s, measure: (t) => Size(t.text.length * t.size * 0.5, t.size * 1.3));
    expect(d.infinite, isTrue);
    final texts = d.layers.expand((l) => l.items).whereType<TextItem>().map((t) => t.text).toList();
    expect(texts, containsAll(['La célula', 'Membrana', 'Núcleo', 'Guarda el ADN.']));
    // Ramas: centro→capítulo y capítulo→idea.
    expect(d.layers.first.strokes.length, 6);
    // Todo dentro del lienzo.
    for (final it in d.layers.expand((l) => l.items)) {
      expect(it.x > 0 && it.x < d.width && it.y > 0 && it.y < d.height, isTrue);
    }
  });
}
