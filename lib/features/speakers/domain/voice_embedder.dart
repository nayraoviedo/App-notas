import 'dart:typed_data';

/// Convierte un trozo de voz en una "huella" numérica (embedding).
/// Dos trozos de la misma persona dan vectores parecidos.
///
/// Implementación: `SherpaVoiceEmbedder` (sherpa_onnx, sin internet).
/// [NoopVoiceEmbedder] apaga la detección automática (útil en pruebas).
abstract interface class VoiceEmbedder {
  bool get isAvailable;

  /// Descarga/carga el modelo. Mientras no termine, [isAvailable] es false.
  Future<void> prepare();

  /// Cantidad de muestras (16 kHz) que necesita por ventana. 1,5 s = 24000.
  int get windowSamples;

  Future<List<double>?> embed(Float32List samples);
}

class NoopVoiceEmbedder implements VoiceEmbedder {
  const NoopVoiceEmbedder();

  @override
  bool get isAvailable => false;

  @override
  Future<void> prepare() async {}

  @override
  int get windowSamples => 24000;

  @override
  Future<List<double>?> embed(Float32List samples) async => null;
}
