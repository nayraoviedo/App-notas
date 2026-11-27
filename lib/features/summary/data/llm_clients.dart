import 'dart:convert';

import 'package:http/http.dart' as http;

class LlmException implements Exception {
  const LlmException(this.message, {this.rateLimited = false, this.badKey = false});
  final String message;

  /// Se alcanzó el límite del plan gratis (conviene esperar o usar otro servicio).
  final bool rateLimited;
  final bool badKey;

  @override
  String toString() => message;
}

/// Un modelo de lenguaje que responde JSON.
abstract interface class LlmClient {
  String get name;
  Future<String> completeJson({required String system, required String user});
}

/// Gemini (Google AI Studio). Plan gratis con límites por día.
class GeminiClient implements LlmClient {
  GeminiClient({required this.apiKey, required this.model, http.Client? client})
      : _http = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _http;

  @override
  String get name => 'Gemini · $model';

  @override
  Future<String> completeJson({required String system, required String user}) async {
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final res = await _http
        .post(
          uri,
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': system}
              ]
            },
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': user}
                ]
              }
            ],
            'generationConfig': {
              'responseMimeType': 'application/json',
              'temperature': 0.3,
            },
          }),
        )
        .timeout(const Duration(minutes: 3));
    _check(res, 'Gemini');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final parts = (body['candidates'] as List?)?.firstOrNull?['content']?['parts'] as List?;
    final text = parts?.map((p) => p['text'] ?? '').join() ?? '';
    if (text.isEmpty) throw const LlmException('Gemini no devolvió texto');
    return text;
  }
}

/// Groq (API compatible con OpenAI). Plan gratis sin tarjeta.
class GroqClient implements LlmClient {
  GroqClient({required this.apiKey, required this.model, http.Client? client})
      : _http = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _http;

  @override
  String get name => 'Groq · $model';

  @override
  Future<String> completeJson({required String system, required String user}) async {
    var res = await _send(system: system, user: user, strictJson: true);
    // El "modo JSON" de Groq rechaza la respuesta entera (400
    // json_validate_failed) si el modelo se equivoca en una coma o se corta.
    // Pasa sobre todo con textos largos: se reintenta sin el modo estricto y
    // el JSON se saca del texto (decodeJsonObject).
    if (res.statusCode == 400 && utf8.decode(res.bodyBytes).contains('json_validate_failed')) {
      res = await _send(system: system, user: user, strictJson: false);
    }
    _check(res, 'Groq');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final text =
        (body['choices'] as List?)?.firstOrNull?['message']?['content'] as String? ?? '';
    if (text.isEmpty) throw const LlmException('Groq no devolvió texto');
    return text;
  }

  Future<http.Response> _send({required String system, required String user, required bool strictJson}) {
    // Los modelos gpt-oss "piensan" antes de responder y ese pensamiento
    // gasta del mismo límite de salida: con poco esfuerzo queda espacio para
    // la respuesta completa.
    final reasoning = model.startsWith('openai/gpt-oss');
    return _http
        .post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'temperature': 0.3,
            'max_completion_tokens': 8192,
            if (reasoning) 'reasoning_effort': 'low',
            if (strictJson) 'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
          }),
        )
        .timeout(const Duration(minutes: 3));
  }
}

void _check(http.Response res, String who) {
  if (res.statusCode == 200) return;
  if (res.statusCode == 429) {
    throw LlmException('$who: se alcanzó el límite del plan gratis', rateLimited: true);
  }
  if (res.statusCode == 401 || res.statusCode == 403) {
    throw LlmException('$who: la clave no es válida', badKey: true);
  }
  final detail = utf8.decode(res.bodyBytes);
  throw LlmException(
      '$who respondió ${res.statusCode}: ${detail.length > 200 ? detail.substring(0, 200) : detail}');
}

/// Quita bloques ```json … ``` si el modelo los agregó.
Map<String, dynamic> decodeJsonObject(String text) {
  var t = text.trim();
  if (t.startsWith('```')) {
    t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    t = t.replaceFirst(RegExp(r'```\s*$'), '');
  }
  final start = t.indexOf('{');
  final end = t.lastIndexOf('}');
  if (start < 0 || end <= start) throw const LlmException('Respuesta sin JSON');
  return jsonDecode(t.substring(start, end + 1)) as Map<String, dynamic>;
}
