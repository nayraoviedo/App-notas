import 'dart:typed_data';

import 'package:whisper_ggml/whisper_ggml.dart';

import '../domain/transcript_segment.dart';
import '../domain/transcription_service.dart';

/// Transcripción 100 % en el teléfono con whisper.cpp (paquete whisper_ggml).
/// El modelo se descarga solo la primera vez y queda guardado.
///
/// - En vivo se usa un modelo pequeño para que no se trabe el teléfono.
/// - Al terminar se re-transcribe el archivo con un modelo mejor y con
///   tiempos por fragmento.
class WhisperTranscriptionService implements TranscriptionService {
  WhisperTranscriptionService({
    this.liveModel = WhisperModel.base,
    this.finalModel = WhisperModel.small,
  });

  final WhisperModel liveModel;
  final WhisperModel finalModel;
  final _controller = WhisperController();

  @override
  Future<LiveTranscription> startLive(
    Stream<Uint8List> pcm16, {
    String lang = 'es',
  }) async {
    final session = await _controller.transcribeLive(
      model: liveModel,
      pcm16Stream: pcm16,
      lang: lang,
    );
    return LiveTranscription(
      partials: session.partials,
      stop: () async {
        await session.stop();
      },
    );
  }

  @override
  Future<List<TranscriptSegment>> transcribeFile(
    String wavPath, {
    String lang = 'es',
    List<String> vocabulary = const [],
    void Function(int percent)? onProgress,
  }) async {
    final result = await _controller.transcribe(
      model: finalModel,
      audioPath: wavPath,
      lang: lang,
      withSegments: true,
      initialPrompt: vocabulary.isEmpty ? null : vocabulary.join(', '),
      onProgress: onProgress,
    );
    final segments = result?.transcription.segments ?? const [];
    return [
      for (final s in segments)
        if (s.text.trim().isNotEmpty)
          TranscriptSegment(
            startMs: s.fromTs.inMilliseconds,
            endMs: s.toTs.inMilliseconds,
            text: s.text.trim(),
          ),
    ];
  }
}
