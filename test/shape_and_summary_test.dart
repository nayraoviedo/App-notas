import 'dart:math' as math;

import 'package:app_notas/features/drawing/application/shape_recognizer.dart';
import 'package:app_notas/features/drawing/domain/drawing.dart';
import 'package:app_notas/features/notes/domain/note_block.dart';
import 'package:app_notas/features/summary/application/summary_service.dart';
import 'package:app_notas/features/summary/data/llm_clients.dart';
import 'package:app_notas/features/transcription/domain/transcript_segment.dart';
import 'package:flutter_test/flutter_test.dart';

List<StrokePoint> _wobblyCircle() => [
      for (var i = 0; i <= 60; i++)
        StrokePoint(
          200 + (100 + (i.isEven ? 3 : -3)) * math.cos(2 * math.pi * i / 60),
          200 + (100 + (i.isEven ? -2 : 2)) * math.sin(2 * math.pi * i / 60),
        ),
    ];

List<StrokePoint> _poly(List<(double, double)> corners, {int perSide = 15}) {
  final pts = <StrokePoint>[];
  for (var i = 0; i < corners.length; i++) {
    final a = corners[i], b = corners[(i + 1) % corners.length];
    for (var k = 0; k < perSide; k++) {
      final t = k / perSide;
      pts.add(StrokePoint(a.$1 + (b.$1 - a.$1) * t + (k.isEven ? 1 : -1),
          a.$2 + (b.$2 - a.$2) * t));
    }
  }
  pts.add(StrokePoint(corners.first.$1 + 2, corners.first.$2 + 2));
  return pts;
}

void main() {
  group('Ajuste de figura', () {
    test('línea', () {
      final pts = [for (var i = 0; i <= 20; i++) StrokePoint(i * 10.0, 50 + (i.isEven ? 2 : -2))];
      expect(ShapeRecognizer.recognize(pts)?.$1, RecognizedShape.line);
    });

    test('círculo', () {
      expect(ShapeRecognizer.recognize(_wobblyCircle())?.$1, RecognizedShape.circle);
    });

    test('rectángulo', () {
      final r = ShapeRecognizer.recognize(_poly([(0, 0), (300, 0), (300, 150), (0, 150)]));
      expect(r?.$1, RecognizedShape.rectangle);
    });

    test('triángulo', () {
      final r = ShapeRecognizer.recognize(_poly([(150, 0), (300, 260), (0, 260)]));
      expect(r?.$1, RecognizedShape.triangle);
    });

    test('garabato no se convierte', () {
      final rnd = math.Random(1);
      final pts = [
        for (var i = 0; i < 80; i++) StrokePoint(rnd.nextDouble() * 300, rnd.nextDouble() * 300),
      ];
      expect(ShapeRecognizer.recognize(pts), isNull);
    });
  });

  group('Resúmenes', () {
    test('tiempos "mm:ss" y "h:mm:ss"', () {
      expect(SummaryService.parseTimestamp('01:29'), 89000);
      expect(SummaryService.parseTimestamp('[1:02:03]'), 3723000);
    });

    test('líneas con hablante, notas y marcas, en orden', () {
      final lines = SummaryService.buildLines(
        const [
          TranscriptSegment(startMs: 0, endMs: 4000, text: 'Hola', speakerId: 'a'),
          TranscriptSegment(startMs: 9000, endMs: 12000, text: 'Tema dos'),
        ],
        const [AudioMarker(atMs: 5000, label: 'Ojo examen'), AudioMarker(atMs: 10000)],
        const {'a': 'Ana'},
      );
      expect(lines, [
        '[00:00] Ana: Hola',
        '[00:05] NOTA DEL USUARIO: Ojo examen',
        '[00:09] Tema dos',
        '[00:10] IMPORTANTE (marcado por el usuario)',
      ]);
    });

    test('divide transcripciones largas en partes', () {
      final chunks = SummaryService.chunkLines(List.filled(100, 'x' * 99), 1000);
      expect(chunks.length, 10);
    });

    test('lee JSON aunque venga entre ```', () {
      expect(decodeJsonObject('```json\n{"a": 1}\n```')['a'], 1);
    });

    test('sin claves avisa que hay que configurarlas', () {
      expect(
        () => SummaryService(const []).summarize(segments: const []),
        throwsA(isA<LlmException>()),
      );
    });
  });
}
