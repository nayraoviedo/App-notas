import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:whisper_ggml/whisper_ggml.dart';

import '../domain/transcript_segment.dart';
import '../domain/transcription_service.dart';

/// Transcripción 100 % en el teléfono con whisper.cpp (paquete whisper_ggml).
///
/// whisper_ggml NO descarga el modelo solo: si falta el archivo, la
/// transcripción falla en silencio. Por eso aquí se descarga primero (una
/// sola vez, ~140 MB, con progreso) y queda guardado en el teléfono.
class WhisperTranscriptionService implements TranscriptionService {
  WhisperTranscriptionService({this.model = WhisperModel.base});

  /// "base" funciona bien en español y es rápido en celulares.
  final WhisperModel model;
  final _controller = WhisperController();
  Future<void>? _downloading;

  @override
  Future<bool> isModelReady() async {
    final f = File(await _controller.getPath(model));
    return f.existsSync() && f.lengthSync() > 1000000;
  }

  @override
  Future<void> ensureModel({void Function(int percent)? onProgress}) {
    // Si ya se está descargando (por ejemplo, desde la grabación en vivo),
    // se espera esa misma descarga.
    return _downloading ??= _download(onProgress).whenComplete(() => _downloading = null);
  }

  Future<void> _download(void Function(int percent)? onProgress) async {
    if (await isModelReady()) return;
    final path = await _controller.getPath(model);
    final part = File('$path.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(model.modelUri);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw TranscriptionException(
            'No se pudo descargar el modelo de voz (error ${res.statusCode}).');
      }
      final total = res.contentLength;
      var got = 0;
      var lastPct = -1;
      final sink = part.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          final pct = got * 100 ~/ total;
          if (pct != lastPct) {
            lastPct = pct;
            onProgress?.call(pct);
          }
        }
      }
      await sink.close();
      if (total > 0 && got < total) {
        throw TranscriptionException('La descarga del modelo de voz se cortó. Intenta de nuevo.');
      }
      await part.rename(path);
    } on SocketException {
      throw TranscriptionException(
          'Para transcribir, la primera vez se necesita internet para bajar el '
          'modelo de voz (unos 140 MB). Conéctate y vuelve a intentar.');
    } on HttpException {
      throw TranscriptionException('No se pudo descargar el modelo de voz. Intenta de nuevo.');
    } finally {
      client.close(force: true);
      if (part.existsSync()) {
        try {
          part.deleteSync();
        } catch (_) {}
      }
    }
  }

  @override
  Future<LiveTranscription> startLive(
    Stream<Uint8List> pcm16, {
    String lang = 'es',
  }) async {
    // En vivo no se espera la descarga: si aún no está el modelo, se avisa y
    // se transcribe todo al terminar.
    if (!await isModelReady()) {
      unawaited(ensureModel().catchError((_) {}));
      throw TranscriptionException('Descargando el modelo de voz…');
    }
    final session = await _controller.transcribeLive(
      model: model,
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
    await ensureModel();
    final result = await _controller.transcribe(
      model: model,
      audioPath: wavPath,
      lang: lang,
      withSegments: true,
      initialPrompt: vocabulary.isEmpty ? null : vocabulary.join(', '),
      onProgress: onProgress,
    );
    if (result == null) {
      throw TranscriptionException('El motor de voz no pudo leer este audio.');
    }
    final segments = result.transcription.segments ?? const [];
    final list = [
      for (final s in segments)
        if (s.text.trim().isNotEmpty && !_isNoise(s.text))
          TranscriptSegment(
            startMs: s.fromTs.inMilliseconds,
            endMs: s.toTs.inMilliseconds,
            text: s.text.trim(),
          ),
    ];
    // Sin segmentos con tiempos: usar el texto completo.
    if (list.isEmpty) {
      final text = result.transcription.text.trim();
      if (text.isNotEmpty && !_isNoise(text)) {
        list.add(TranscriptSegment(startMs: 0, endMs: 0, text: text));
      }
    }
    return list;
  }

  /// Marcas que Whisper pone cuando no hay voz ("[BLANK_AUDIO]", "(música)").
  static bool _isNoise(String t) {
    final s = t.trim();
    return RegExp(r'^[\[\(].*[\]\)]$').hasMatch(s);
  }
}
