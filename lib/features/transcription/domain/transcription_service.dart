import 'dart:typed_data';

import 'transcript_segment.dart';

/// Sesión de transcripción en vivo mientras se graba.
class LiveTranscription {
  LiveTranscription({required this.partials, required Future<void> Function() stop})
      : _stop = stop;

  /// Cada evento trae el texto completo hasta ahora (no solo lo nuevo).
  final Stream<String> partials;
  final Future<void> Function() _stop;

  Future<void> stop() => _stop();
}

/// Contrato del motor de transcripción. Permite cambiar Whisper local por
/// una API en la nube sin tocar el resto de la app.
abstract interface class TranscriptionService {
  /// Transcripción en vivo (aproximada) a partir de PCM16 mono 16 kHz.
  Future<LiveTranscription> startLive(
    Stream<Uint8List> pcm16, {
    String lang = 'es',
  });

  /// Transcripción final y precisa de un archivo WAV, con tiempos.
  /// [vocabulary]: términos técnicos o nombres propios que se escriben bien.
  Future<List<TranscriptSegment>> transcribeFile(
    String wavPath, {
    String lang = 'es',
    List<String> vocabulary = const [],
    void Function(int percent)? onProgress,
  });
}
