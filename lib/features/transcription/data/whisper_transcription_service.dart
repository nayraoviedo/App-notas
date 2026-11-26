import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:whisper_ggml/whisper_ggml.dart';

import '../domain/transcript_segment.dart';
import '../domain/transcription_service.dart';
import '../../../core/platform_info.dart';
import '../../recording/data/pcm_resample.dart';
import 'package:path_provider/path_provider.dart';

/// Transcripción 100 % en el teléfono con whisper.cpp (paquete whisper_ggml).
///
/// whisper_ggml NO descarga el modelo solo: si falta el archivo, la
/// transcripción falla en silencio. Por eso aquí se descarga primero (una
/// sola vez, ~57 MB, reanudable y con progreso) y queda guardado.
const _desktopMsg = 'En la compu se transcribe con internet: pon tu clave de Groq o Gemini en Ajustes.';

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

  /// Se baja la versión comprimida del modelo "base" (q5_1, ~57 MB en vez
  /// de 147 MB): transcribe casi igual y descarga mucho más rápido. Se prueba
  /// también un espejo por si Hugging Face anda lento.
  static final _sources = [
    Uri.parse('https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin'),
    Uri.parse('https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin'),
  ];

  Future<void> _download(void Function(int percent)? onProgress) async {
    if (await isModelReady()) return;
    final path = await _controller.getPath(model);
    TranscriptionException? last;
    for (final uri in _sources) {
      try {
        await _downloadFrom(uri, path, onProgress);
        return;
      } on TranscriptionException catch (e) {
        last = e;
      }
    }
    throw last ??
        TranscriptionException('No se pudo descargar el modelo de voz.');
  }

  /// Descarga reanudable: si se corta, la próxima vez sigue donde quedó.
  Future<void> _downloadFrom(Uri uri, String path, void Function(int percent)? onProgress) async {
    final part = File('$path.part');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 20);
    try {
      var have = part.existsSync() ? part.lengthSync() : 0;
      final req = await client.getUrl(uri);
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        have = 0; // el servidor no reanuda: empezar de nuevo
      } else if (res.statusCode != 206) {
        throw TranscriptionException(
            'No se pudo descargar el modelo de voz (error ${res.statusCode}).');
      }
      final total = res.contentLength < 0 ? -1 : res.contentLength + have;
      var got = have;
      var lastPct = -1;
      final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
      try {
        // Si pasan 30 s sin recibir nada, se corta (y se reanuda luego).
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
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
      } finally {
        await sink.close();
      }
      if (total > 0 && got < total) {
        throw TranscriptionException('La descarga se cortó; vuelve a intentar y seguirá donde quedó.');
      }
      await part.rename(path);
    } on TimeoutException {
      throw TranscriptionException(
          'La descarga del modelo de voz está muy lenta. Vuelve a intentar (sigue donde quedó) '
          'o pon una clave gratis de Groq en Ajustes para transcribir sin descargar nada.');
    } on SocketException {
      throw TranscriptionException(
          'Para transcribir en el teléfono, la primera vez hay que bajar el modelo de voz '
          '(~57 MB) y no hay conexión. También puedes poner una clave gratis de Groq en Ajustes.');
    } on HttpException {
      throw TranscriptionException('No se pudo descargar el modelo de voz. Intenta de nuevo.');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<LiveTranscription> startLive(
    Stream<Uint8List> pcm16, {
    String lang = 'es',
  }) async {
    if (!isPhone) throw TranscriptionException(_desktopMsg);
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
    if (!isPhone) throw TranscriptionException(_desktopMsg);
    await ensureModel();
    // Las grabaciones en alta calidad (48 kHz) se bajan a 16 kHz, que es lo
    // que lee whisper.
    final temp = wavSampleRate(wavPath) == 48000
        ? '${(await getTemporaryDirectory()).path}/w16_${DateTime.now().microsecondsSinceEpoch}.wav'
        : null;
    final input = temp == null ? wavPath : await wav48To16(wavPath, temp);
    final result = await _controller
        .transcribe(
      model: model,
      audioPath: input,
      lang: lang,
      withSegments: true,
      initialPrompt: vocabulary.isEmpty ? null : vocabulary.join(', '),
      onProgress: onProgress,
    )
        .whenComplete(() {
      if (temp != null) File(temp).delete().ignore();
    });
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
