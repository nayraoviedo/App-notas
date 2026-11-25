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

/// Elige el motor: con clave de Groq transcribe en la nube (rápido y sin
/// descargas); si no hay clave o falla la conexión, usa Whisper en el
/// teléfono.
class SmartTranscriptionService implements TranscriptionService {
  SmartTranscriptionService({
    required this.local,
    required this.groqKey,
    required this.compress,
  });

  final TranscriptionService local;

  /// Lee la clave de Groq guardada (null = no hay).
  final Future<String?> Function() groqKey;

  /// Convierte el WAV a un formato más liviano para subirlo.
  final Future<String> Function(String wavPath) compress;

  Future<bool> _hasGroq() async => ((await groqKey()) ?? '').trim().isNotEmpty;

  @override
  Future<bool> isModelReady() async => await _hasGroq() || await local.isModelReady();

  @override
  Future<void> ensureModel({void Function(int percent)? onProgress}) async {
    if (await _hasGroq()) return;
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
    final key = (await groqKey())?.trim();
    if (key != null && key.isNotEmpty) {
      onProgress?.call(10);
      try {
        final upload = await compress(wavPath);
        onProgress?.call(30);
        final result = await GroqTranscriber(apiKey: key)
            .transcribe(upload, lang: lang, vocabulary: vocabulary);
        onProgress?.call(100);
        return result;
      } on TranscriptionException {
        // Si el modelo local ya está, se usa como respaldo; si no, se avisa.
        if (!await local.isModelReady()) rethrow;
      }
    }
    return local.transcribeFile(wavPath, lang: lang, vocabulary: vocabulary, onProgress: onProgress);
  }
}
