import '../../../core/utils/time_format.dart';
import '../../notes/domain/note_block.dart';
import '../../transcription/domain/transcript_segment.dart';
import '../data/llm_clients.dart';
import '../domain/summary.dart';

/// Arma el resumen completo y por capítulos de una grabación.
///
/// Las clases largas se resumen por partes (para no pasar los límites de los
/// planes gratis) y luego se unen. Si el primer servicio falla por límite o
/// clave, se prueba con el siguiente de la lista.
class SummaryService {
  SummaryService(this.clients, {this.maxChunkChars = 12000, this.language = 'es'});

  /// En orden de preferencia.
  final List<LlmClient> clients;
  final int maxChunkChars;
  final String language;

  Future<TranscriptSummary> summarize({
    required List<TranscriptSegment> segments,
    List<AudioMarker> markers = const [],
    Map<String, String> speakerNames = const {},
    void Function(String status)? onStatus,
  }) async {
    if (clients.isEmpty) {
      throw const LlmException(
          'Agrega una clave gratis de Gemini o Groq en Ajustes para generar resúmenes.');
    }
    if (segments.isEmpty) throw const LlmException('La grabación no tiene transcripción.');

    final lines = buildLines(segments, markers, speakerNames);
    final chunks = chunkLines(lines, maxChunkChars);

    if (chunks.length == 1) {
      onStatus?.call('Resumiendo…');
      final r = await _ask(_fullPrompt(chunks.single));
      return _parseFull(r.$1, r.$2);
    }

    // Por partes: capítulos, puntos clave y tareas de cada parte.
    final chapters = <Chapter>[];
    final keyPoints = <String>[];
    final tasks = <SummaryTask>[];
    String provider = '';
    for (var i = 0; i < chunks.length; i++) {
      onStatus?.call('Resumiendo parte ${i + 1} de ${chunks.length}…');
      final r = await _ask(_chunkPrompt(chunks[i], i + 1, chunks.length));
      provider = r.$2;
      chapters.addAll(_chapters(r.$1['chapters']));
      keyPoints.addAll(_strings(r.$1['key_points']));
      tasks.addAll(_tasks(r.$1['tasks']));
    }

    onStatus?.call('Uniendo el resumen…');
    final outline = chapters
        .map((c) => '[${formatMs(c.atMs)}] ${c.title}: ${c.summary}')
        .join('\n');
    final r = await _ask((
      _system,
      'A partir de estos capítulos de una grabación, escribe el título general y '
          'un resumen completo de 1 a 3 párrafos. Responde JSON: '
          '{"title": string, "overview": string, "key_points": [string]} '
          '(máximo 8 puntos clave, sin repetir).\n\nCAPÍTULOS:\n$outline\n\n'
          'PUNTOS CLAVE PARCIALES:\n${keyPoints.join('\n')}',
    ));
    return TranscriptSummary(
      title: r.$1['title'] as String? ?? '',
      overview: r.$1['overview'] as String? ?? '',
      chapters: chapters..sort((a, b) => a.atMs.compareTo(b.atMs)),
      keyPoints: _strings(r.$1['key_points']).isNotEmpty
          ? _strings(r.$1['key_points'])
          : keyPoints.take(8).toList(),
      tasks: tasks,
      provider: provider,
    );
  }

  // ------------------------------------------------------------- Prompts

  String get _system =>
      'Eres un asistente que resume clases y reuniones grabadas. Responde '
      '${language == 'auto' ? 'en el mismo idioma de la transcripción' : 'en el idioma "$language"'}, '
      'con lenguaje claro, sin inventar nada que no esté en la transcripción. '
      'La transcripción viene de reconocimiento de voz y puede tener errores: '
      'interpreta con sentido común. Las líneas "NOTA DEL USUARIO" y "IMPORTANTE" '
      'las marcó quien grabó: dales prioridad. Responde solo JSON válido.';

  static const _chapterSpec =
      '"chapters": [{"start": "mm:ss", "title": string, "summary": string}] '
      '(un capítulo por cada cambio de tema; "start" debe ser uno de los tiempos '
      'entre corchetes de la transcripción; 2 a 4 oraciones por capítulo)';

  static const _extraSpec =
      '"key_points": [string] (máximo 8), "tasks": [{"task": string, "due": string|null}] '
      '(tareas, entregas o fechas mencionadas; vacío si no hay)';

  (String, String) _fullPrompt(String transcript) => (
        _system,
        'Resume esta grabación. Responde JSON: {"title": string, "overview": string '
            '(resumen completo de 1 a 3 párrafos), $_chapterSpec, $_extraSpec}.\n\n'
            'TRANSCRIPCIÓN:\n$transcript',
      );

  (String, String) _chunkPrompt(String transcript, int part, int total) => (
        _system,
        'Esta es la parte $part de $total de una grabación. Responde JSON: '
            '{$_chapterSpec, $_extraSpec}.\n\nTRANSCRIPCIÓN (parte $part):\n$transcript',
      );

  // --------------------------------------------------------- Llamadas

  Future<(Map<String, dynamic>, String)> _ask((String, String) prompt) async {
    LlmException? last;
    for (final c in clients) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final text = await c.completeJson(system: prompt.$1, user: prompt.$2);
          return (decodeJsonObject(text), c.name);
        } on LlmException catch (e) {
          last = e;
          if (e.badKey) break; // probar el siguiente servicio
          if (e.rateLimited && attempt == 0) {
            // Los límites por minuto se liberan rápido; reintentar una vez.
            await Future<void>.delayed(const Duration(seconds: 20));
            continue;
          }
          break;
        } on FormatException catch (e) {
          last = LlmException('Respuesta inválida: ${e.message}');
        }
      }
    }
    throw last ?? const LlmException('No se pudo generar el resumen');
  }

  TranscriptSummary _parseFull(Map<String, dynamic> j, String provider) => TranscriptSummary(
        title: j['title'] as String? ?? '',
        overview: j['overview'] as String? ?? '',
        chapters: _chapters(j['chapters']),
        keyPoints: _strings(j['key_points']),
        tasks: _tasks(j['tasks']),
        provider: provider,
      );

  static List<Chapter> _chapters(Object? raw) => [
        if (raw is List)
          for (final c in raw)
            if (c is Map)
              Chapter(
                atMs: parseTimestamp('${c['start'] ?? '0:00'}'),
                title: '${c['title'] ?? ''}',
                summary: '${c['summary'] ?? ''}',
              ),
      ];

  static List<String> _strings(Object? raw) =>
      raw is List ? raw.map((e) => '$e').where((s) => s.trim().isNotEmpty).toList() : [];

  static List<SummaryTask> _tasks(Object? raw) => [
        if (raw is List)
          for (final t in raw)
            if (t is Map && '${t['task'] ?? ''}'.trim().isNotEmpty)
              SummaryTask(
                task: '${t['task']}',
                due: t['due'] == null || '${t['due']}' == 'null' ? null : '${t['due']}',
              ),
      ];

  // ---------------------------------------------------------- Utilidades

  /// Una línea por párrafo: "[mm:ss] Ana: texto", más notas y marcas ⭐.
  static List<String> buildLines(
    List<TranscriptSegment> segments,
    List<AudioMarker> markers,
    Map<String, String> speakerNames,
  ) {
    final items = <(int, String)>[
      for (final s in segments)
        (
          s.startMs,
          '[${formatMs(s.startMs)}] '
              '${s.speakerId != null && speakerNames[s.speakerId] != null ? '${speakerNames[s.speakerId]}: ' : ''}'
              '${s.text}',
        ),
      for (final m in markers)
        (
          m.atMs,
          m.isQuickNote
              ? '[${formatMs(m.atMs)}] NOTA DEL USUARIO: ${m.label}'
              : '[${formatMs(m.atMs)}] IMPORTANTE (marcado por el usuario)',
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return items.map((e) => e.$2).toList();
  }

  static List<String> chunkLines(List<String> lines, int maxChars) {
    final chunks = <String>[];
    final buf = StringBuffer();
    for (final l in lines) {
      if (buf.length > 0 && buf.length + l.length + 1 > maxChars) {
        chunks.add(buf.toString());
        buf.clear();
      }
      buf.writeln(l);
    }
    if (buf.length > 0) chunks.add(buf.toString());
    return chunks;
  }

  /// "mm:ss" o "h:mm:ss" → milisegundos.
  static int parseTimestamp(String t) {
    final parts = t.replaceAll(RegExp(r'[\[\]\s]'), '').split(':');
    var seconds = 0;
    for (final p in parts) {
      seconds = seconds * 60 + (int.tryParse(p) ?? 0);
    }
    return seconds * 1000;
  }
}
