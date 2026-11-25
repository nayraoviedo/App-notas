import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:app_notas/features/speakers/application/speaker_tracker.dart';
import 'package:app_notas/features/speakers/domain/voice_embedder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Embedder falso: la "huella" depende de la frecuencia del tono.
class _FakeEmbedder implements VoiceEmbedder {
  @override
  bool get isAvailable => true;
  @override
  int get windowSamples => 1600; // 0,1 s para que el test sea rápido

  @override
  Future<List<double>?> embed(Float32List samples) async {
    var crossings = 0;
    for (var i = 1; i < samples.length; i++) {
      if ((samples[i - 1] < 0) != (samples[i] < 0)) crossings++;
    }
    return crossings > 100 ? [0, 1] : [1, 0];
  }
}

Uint8List _tone(double hz, int samples) {
  final b = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    final v = (math.sin(2 * math.pi * hz * i / 16000) * 0.5 * 32767).round();
    b.setInt16(i * 2, v, Endian.little);
  }
  return b.buffer.asUint8List();
}

void main() {
  test('sugiere cambio de hablante tras dos ventanas distintas', () async {
    final tracker = SpeakerTracker(_FakeEmbedder());
    final suggestions = [];
    final sub = tracker.suggestions.listen(suggestions.add);

    for (var i = 0; i < 3; i++) {
      tracker.addPcm16(_tone(200, 1600)); // voz grave
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 3; i++) {
      tracker.addPcm16(_tone(2000, 1600)); // voz aguda
      await Future<void>.delayed(Duration.zero);
    }

    expect(suggestions, hasLength(1));
    tracker.confirm('luis');
    expect(tracker.turns.single.speakerId, 'luis');
    await sub.cancel();
    await tracker.dispose();
  });

  test('marcar a mano quién habla funciona sin modelo de voz', () {
    final tracker = SpeakerTracker(const NoopVoiceEmbedder())
      ..markTurn('ana', 0)
      ..markTurn('luis', 5000);
    expect(tracker.turns.map((t) => t.speakerId), ['ana', 'luis']);
  });

  test('similitud coseno', () {
    expect(SpeakerTracker.cosineSimilarity([1, 0], [1, 0]), closeTo(1, 1e-9));
    expect(SpeakerTracker.cosineSimilarity([1, 0], [0, 1]), closeTo(0, 1e-9));
  });
}
