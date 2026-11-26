import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/transcript_segment.dart';
import '../domain/transcription_service.dart';

/// Transcripción en la nube con Whisper de Groq (gratis con una clave de
/// console.groq.com). Es muy rápida y no necesita bajar ningún modelo; el
/// audio se envía a Groq solo para transcribirlo.
class GroqTranscriber {
  GroqTranscriber({required this.apiKey, this.model = 'whisper-large-v3-turbo', http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  /// Límite del plan gratis (25 MB por archivo).
  static const maxBytes = 24 * 1024 * 1024;

  Future<List<TranscriptSegment>> transcribe(
    String audioPath, {
    String lang = 'es',
    List<String> vocabulary = const [],
  }) async {
    final file = File(audioPath);
    if (file.lengthSync() > maxBytes) {
      throw TranscriptionException('La grabación es muy larga para Groq (máx. 25 MB).');
    }
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions'),
    )
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = model
      ..fields['response_format'] = 'verbose_json'
      ..fields['temperature'] = '0';
    if (lang != 'auto') req.fields['language'] = lang;
    if (vocabulary.isNotEmpty) req.fields['prompt'] = vocabulary.join(', ');
    req.files.add(await http.MultipartFile.fromPath('file', audioPath));

    final http.Response res;
    try {
      res = await http.Response.fromStream(
          await _client.send(req).timeout(const Duration(minutes: 3)));
    } on SocketException {
      throw TranscriptionException('Sin conexión para transcribir con Groq.');
    }
    if (res.statusCode == 401) {
      throw TranscriptionException('La clave de Groq no es válida. Revísala en Ajustes.');
    }
    if (res.statusCode == 429) {
      throw TranscriptionException('Groq está ocupado o se alcanzó el límite gratis. Intenta en un rato.');
    }
    if (res.statusCode != 200) {
      throw TranscriptionException('Groq respondió con error ${res.statusCode}.');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
    final segments = (json['segments'] as List? ?? const []).cast<Map>();
    final out = <TranscriptSegment>[
      for (final s in segments)
        if ((s['text'] as String? ?? '').trim().isNotEmpty)
          TranscriptSegment(
            startMs: (((s['start'] as num?) ?? 0) * 1000).round(),
            endMs: (((s['end'] as num?) ?? 0) * 1000).round(),
            text: (s['text'] as String).trim(),
          ),
    ];
    if (out.isEmpty) {
      final text = (json['text'] as String? ?? '').trim();
      if (text.isNotEmpty) out.add(TranscriptSegment(startMs: 0, endMs: 0, text: text));
    }
    return out;
  }
}

/// Transcripción con Gemini (Google AI Studio, gratis con clave). Se usa
/// como respaldo cuando Groq llega a su límite o falla.
class GeminiTranscriber {
  GeminiTranscriber({required this.apiKey, required this.model, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  static const _base = 'https://generativelanguage.googleapis.com';

  Future<List<TranscriptSegment>> transcribe(
    String audioPath, {
    String lang = 'es',
    List<String> vocabulary = const [],
  }) async {
    // Un enlace de YouTube: Gemini lo ve directamente (videos públicos).
    final isLink = audioPath.startsWith('http://') || audioPath.startsWith('https://');
    final Map<String, Object> audioPart;
    if (isLink) {
      audioPart = {
        'file_data': {'file_uri': audioPath}
      };
    } else {
      final file = File(audioPath);
      final bytes = await file.readAsBytes();
      final mime = audioPath.toLowerCase().endsWith('.wav')
          ? 'audio/wav'
          : audioPath.toLowerCase().endsWith('.mp3')
              ? 'audio/mp3'
              : 'audio/mp4';
      // Hasta ~14 MB va dentro del pedido; más grande se sube primero.
      audioPart = bytes.length < 14 * 1024 * 1024
          ? {
              'inline_data': {'mime_type': mime, 'data': base64Encode(bytes)}
            }
          : {
              'file_data': {'mime_type': mime, 'file_uri': await _upload(bytes, mime)}
            };
    }
    final language = switch (lang) {
      'es' => 'español',
      'en' => 'inglés',
      'auto' => 'el idioma en que se habla',
      _ => lang,
    };
    final prompt = 'Transcribe ${isLink ? 'lo que se dice en este video' : 'este audio'} COMPLETO, palabra por palabra, en $language. '
        'No resumas ni omitas partes. Divide en fragmentos de 1 o 2 oraciones con el minuto '
        'en que empieza cada uno (formato MM:SS). '
        '${vocabulary.isEmpty ? '' : 'Palabras que pueden aparecer: ${vocabulary.join(', ')}. '}'
        'Devuelve JSON: {"segments": [{"start": "MM:SS", "end": "MM:SS", "text": "..."}]}';
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$_base/v1beta/models/$model:generateContent'),
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    audioPart,
                    {'text': prompt},
                  ],
                }
              ],
              'generationConfig': {
                'responseMimeType': 'application/json',
                'temperature': 0,
                'maxOutputTokens': 65536,
              },
            }),
          )
          .timeout(Duration(minutes: isLink ? 12 : 6));
    } on SocketException {
      throw TranscriptionException('Sin conexión para transcribir con Gemini.');
    }
    if (res.statusCode == 400 || res.statusCode == 403) {
      throw TranscriptionException('La clave de Gemini no es válida o el modelo no acepta audio. Revisa Ajustes.');
    }
    if (res.statusCode == 429) {
      throw TranscriptionException('Gemini también llegó a su límite gratis. Intenta en un rato.');
    }
    if (res.statusCode != 200) {
      throw TranscriptionException('Gemini respondió con error ${res.statusCode}.');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final parts = (body['candidates'] as List?)?.firstOrNull?['content']?['parts'] as List?;
    final text = parts?.map((p) => p['text'] ?? '').join() ?? '';
    return parseGeminiSegments(text);
  }

  /// Subida "reanudable" a la API de archivos de Gemini; devuelve el uri.
  Future<String> _upload(List<int> bytes, String mime) async {
    final start = await _client.post(
      Uri.parse('$_base/upload/v1beta/files'),
      headers: {
        'x-goog-api-key': apiKey,
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': '${bytes.length}',
        'X-Goog-Upload-Header-Content-Type': mime,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'file': {'display_name': 'grabacion'}
      }),
    );
    final url = start.headers['x-goog-upload-url'];
    if (url == null) throw TranscriptionException('No se pudo subir el audio a Gemini (${start.statusCode}).');
    final up = await _client
        .post(
          Uri.parse(url),
          headers: {
            'Content-Length': '${bytes.length}',
            'X-Goog-Upload-Offset': '0',
            'X-Goog-Upload-Command': 'upload, finalize',
          },
          body: bytes,
        )
        .timeout(const Duration(minutes: 5));
    final uri = ((jsonDecode(utf8.decode(up.bodyBytes)) as Map)['file'] as Map?)?['uri'] as String?;
    if (uri == null) throw TranscriptionException('Gemini no recibió el audio (${up.statusCode}).');
    // Esperar a que el archivo quede listo (suele ser inmediato).
    for (var i = 0; i < 20; i++) {
      final name = uri.substring(uri.indexOf('files/'));
      final st = await _client.get(Uri.parse('$_base/v1beta/$name'), headers: {'x-goog-api-key': apiKey});
      final state = (jsonDecode(utf8.decode(st.bodyBytes)) as Map)['state'];
      if (state == null || state == 'ACTIVE') break;
      if (state == 'FAILED') throw TranscriptionException('Gemini no pudo leer el audio.');
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return uri;
  }
}

/// Lee {"segments":[{"start":"MM:SS","end":"MM:SS","text":"…"}]}.
List<TranscriptSegment> parseGeminiSegments(String raw) {
  var t = raw.trim();
  if (t.startsWith('```')) t = t.replaceAll(RegExp(r'^```(json)?|```$', multiLine: true), '').trim();
  final Object? json;
  try {
    json = jsonDecode(t);
  } catch (_) {
    return t.isEmpty ? const [] : [TranscriptSegment(startMs: 0, endMs: 0, text: t)];
  }
  final list = json is Map ? json['segments'] : json;
  if (list is! List) return const [];
  int ms(Object? v) {
    if (v is num) return (v * 1000).round();
    final p = '${v ?? ''}'.split(':').map((x) => double.tryParse(x.trim()) ?? 0).toList();
    if (p.isEmpty) return 0;
    var sec = 0.0;
    for (final x in p) {
      sec = sec * 60 + x;
    }
    return (sec * 1000).round();
  }

  final out = <TranscriptSegment>[];
  for (final (i, s) in list.indexed) {
    if (s is! Map) continue;
    final text = '${s['text'] ?? ''}'.trim();
    if (text.isEmpty) continue;
    final start = ms(s['start']);
    var end = ms(s['end']);
    if (end <= start) {
      final next = i + 1 < list.length && list[i + 1] is Map ? ms((list[i + 1] as Map)['start']) : start + 5000;
      end = next > start ? next : start + 5000;
    }
    out.add(TranscriptSegment(startMs: start, endMs: end, text: text));
  }
  return out;
}

/// Elige el motor: con clave de Groq transcribe en la nube (rápido y sin
/// descargas); si no hay clave o falla la conexión, usa Whisper en el
/// teléfono.
class SmartTranscriptionService implements TranscriptionService {
  SmartTranscriptionService({
    required this.local,
    required this.groqKey,
    required this.compress,
    this.geminiKey,
    this.geminiModel = 'gemini-3.6-flash',
  });

  final TranscriptionService local;

  /// Lee la clave de Groq guardada (null = no hay).
  final Future<String?> Function() groqKey;

  /// Clave de Gemini, de respaldo si Groq llega al límite o falla.
  final Future<String?> Function()? geminiKey;
  final String geminiModel;

  /// Convierte el WAV a un formato más liviano para subirlo.
  final Future<String> Function(String wavPath) compress;

  Future<String?> _key(Future<String?> Function()? f) async {
    final k = (await f?.call())?.trim();
    return k == null || k.isEmpty ? null : k;
  }

  Future<bool> _hasCloud() async => await _key(groqKey) != null || await _key(geminiKey) != null;

  @override
  Future<bool> isModelReady() async => await _hasCloud() || await local.isModelReady();

  @override
  Future<void> ensureModel({void Function(int percent)? onProgress}) async {
    if (await _hasCloud()) return;
    await local.ensureModel(onProgress: onProgress);
  }

  @override
  Future<LiveTranscription> startLive(Stream<Uint8List> pcm16, {String lang = 'es'}) =>
      local.startLive(pcm16, lang: lang);

  @override
  Future<List<TranscriptSegment>> transcribeFile(
    String wavPath, {
    String lang = 'es',
    List<String> vocabulary = const [],
    void Function(int percent)? onProgress,
  }) async {
    final groq = await _key(groqKey);
    final gemini = await _key(geminiKey);
    TranscriptionException? lastError;
    String? compressed;
    Future<String> small({required int overBytes}) async {
      // Grabaciones cortas se suben tal cual; las largas se comprimen.
      if (File(wavPath).lengthSync() <= overBytes) return wavPath;
      if (compressed != null) return compressed!;
      try {
        compressed = await compress(wavPath).timeout(const Duration(minutes: 2));
      } catch (_) {
        compressed = wavPath;
      }
      return compressed!;
    }

    // 1) Groq (rápido).
    if (groq != null) {
      onProgress?.call(10);
      try {
        final upload = await small(overBytes: 18 * 1024 * 1024);
        onProgress?.call(30);
        final result = await GroqTranscriber(apiKey: groq).transcribe(upload, lang: lang, vocabulary: vocabulary);
        onProgress?.call(100);
        return result;
      } on TranscriptionException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = TranscriptionException('Groq falló: $e');
      }
    }
    // 2) Gemini de respaldo (o principal si no hay Groq).
    if (gemini != null) {
      onProgress?.call(40);
      try {
        final upload = await small(overBytes: 10 * 1024 * 1024);
        onProgress?.call(55);
        final result = await GeminiTranscriber(apiKey: gemini, model: geminiModel)
            .transcribe(upload, lang: lang, vocabulary: vocabulary);
        onProgress?.call(100);
        if (result.isNotEmpty) return result;
      } on TranscriptionException catch (e) {
        lastError = TranscriptionException(
            lastError == null ? e.message : '${lastError.message}\nY con Gemini: ${e.message}');
      } catch (e) {
        lastError = TranscriptionException('Gemini falló: $e');
      }
    }
    // 3) En el teléfono, si el modelo ya está; si no, se avisa el error.
    if (lastError != null && !await local.isModelReady()) throw lastError;
    return local.transcribeFile(wavPath, lang: lang, vocabulary: vocabulary, onProgress: onProgress);
  }
}
