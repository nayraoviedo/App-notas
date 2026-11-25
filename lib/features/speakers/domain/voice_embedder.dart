import 'dart:typed_data';

/// Convierte un trozo de voz en una "huella" numérica (embedding).
/// Dos trozos de la misma persona dan vectores parecidos.
///
/// Implementación recomendada: `sherpa_onnx` (SpeakerEmbeddingExtractor) con
/// un modelo pequeño como 3D-Speaker o WeSpeaker, que funciona sin internet.
/// Mientras no esté conectada, se usa [NoopVoiceEmbedder] y la app
/// simplemente no sugiere cambios de hablante.
abstract interface class VoiceEmbedder {
  bool get isAvailable;

  /// Cantidad de muestras (16 kHz) que necesita por ventana. 1,5 s = 24000.
  int get windowSamples;

  Future<List<double>?> embed(Float32List samples);
}

class NoopVoiceEmbedder implements VoiceEmbedder {
  const NoopVoiceEmbedder();

  @override
  bool get isAvailable => false;

  @override
  int get windowSamples => 24000;

  @override
  Future<List<double>?> embed(Float32List samples) async => null;
}
