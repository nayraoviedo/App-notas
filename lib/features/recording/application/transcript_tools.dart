import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
import '../../drawing/domain/canvas_item.dart';
import '../../drawing/domain/drawing.dart';
import '../../study/presentation/study_screen.dart' show availableLlms;
import '../../transcription/domain/transcript_segment.dart';

/// Qué versión de la transcripción se está mostrando.
enum TranscriptVersion { original, corrected }

File _originalFile(String audioPath) => File('$audioPath.original.json');
File _correctedFile(String audioPath) => File('$audioPath.ia.json');

Map<int, String> _readMap(File f) {
  if (!f.existsSync()) return const {};
  try {
    return {
      for (final e in (jsonDecode(f.readAsStringSync()) as Map).entries) int.parse(e.key as String): e.value as String,
    };
  } catch (_) {
    return const {};
  }
}

Future<void> _writeMap(File f, Map<int, String> m) =>
    f.writeAsString(jsonEncode({for (final e in m.entries) '${e.key}': e.value}));

/// ¿Ya hay una versión corregida con IA? ¿y cuál se muestra?
(bool hasCorrected, TranscriptVersion showing) transcriptVersionInfo(String audioPath) {
  final has = _correctedFile(audioPath).existsSync();
  final showing = has && _originalFile(audioPath).existsSync() && File('$audioPath.usando-ia').existsSync()
      ? TranscriptVersion.corrected
      : TranscriptVersion.original;
  return (has, showing);
}

/// Corrige la transcripción con IA (ortografía, puntuación y palabras mal
/// entendidas) sin resumir ni cambiar el sentido. Guarda la original para
/// poder volver a ella.
Future<int> correctTranscriptWithAi(
  WidgetRef ref, {
  required String blockId,
  required String audioPath,
  void Function(int percent)? onProgress,
}) async {
  final segments = (await ref.read(segmentsProvider(blockId).future)).where((s) => s.id != null).toList();
  if (segments.isEmpty) throw Exception('Todavía no hay transcripción para corregir.');
  final llms = await availableLlms(ref);
  if (llms.isEmpty) throw Exception('Pon una clave de Groq o Gemini en Ajustes para corregir con IA.');

  // Guardar la original (solo la primera vez).
  final orig = _originalFile(audioPath);
  if (!orig.existsSync()) await _writeMap(orig, {for (final s in segments) s.id!: s.text});

  const system = 'Eres un corrector de transcripciones de clases en español. Corrige ortografía, '
      'tildes, puntuación, mayúsculas y palabras que claramente se entendieron mal por el sonido. '
      'NO resumas, NO agregues ni quites ideas, NO cambies el orden. Devuelve JSON: '
      '{"segments": [{"i": número, "text": "texto corregido"}]} con TODOS los fragmentos recibidos.';
  final corrected = <int, String>{};
  const chunk = 30;
  for (var start = 0; start < segments.length; start += chunk) {
    final part = segments.skip(start).take(chunk).toList();
    final user = [for (final (k, s) in part.indexed) '[$k] ${s.text}'].join('\n');
    Map<String, Object?>? json;
    Object? lastError;
    for (final llm in llms) {
      try {
        json = jsonDecode(await llm.completeJson(system: system, user: user)) as Map<String, Object?>;
        break;
      } catch (e) {
        lastError = e;
      }
    }
    if (json == null) throw Exception('La IA no respondió: $lastError');
    for (final item in (json['segments'] as List? ?? const [])) {
      if (item is! Map) continue;
      final i = item['i'], t = item['text'];
      if (i is int && i >= 0 && i < part.length && t is String && t.trim().isNotEmpty) {
        corrected[part[i].id!] = t.trim();
      }
    }
    onProgress?.call(((start + part.length) * 100 / segments.length).round());
  }
  await _writeMap(_correctedFile(audioPath), corrected);
  await showTranscriptVersion(ref, audioPath: audioPath, version: TranscriptVersion.corrected);
  return corrected.length;
}

/// Cambia lo que se ve (y lo que se exporta/resume) entre la original y la
/// corregida.
Future<void> showTranscriptVersion(
  WidgetRef ref, {
  required String audioPath,
  required TranscriptVersion version,
}) async {
  final map = _readMap(version == TranscriptVersion.original ? _originalFile(audioPath) : _correctedFile(audioPath));
  final repo = ref.read(notesRepositoryProvider);
  for (final e in map.entries) {
    await repo.updateSegmentText(e.key, e.value);
  }
  final flag = File('$audioPath.usando-ia');
  if (version == TranscriptVersion.corrected) {
    await flag.writeAsString('1');
  } else if (flag.existsSync()) {
    await flag.delete();
  }
}

// ------------------------------------------------------------ A las notas

/// Junta los fragmentos en párrafos: mismo hablante y no muy largos.
List<(int atMs, String? speakerId, String text)> transcriptParagraphs(List<TranscriptSegment> segs,
    {int maxChars = 700}) {
  final out = <(int, String?, String)>[];
  for (final s in segs) {
    final t = s.text.trim();
    if (t.isEmpty) continue;
    if (out.isNotEmpty && out.last.$2 == s.speakerId && out.last.$3.length + t.length < maxChars) {
      final last = out.removeLast();
      out.add((last.$1, last.$2, '${last.$3} $t'));
    } else {
      out.add((s.startMs, s.speakerId, t));
    }
  }
  return out;
}

/// Hojas rayadas con la transcripción escrita (letra manuscrita): el
/// minuto y quién habla, y el párrafo. Si no entra, sigue en otra hoja.
List<Drawing> transcriptPages(
  String title,
  List<(int atMs, String? speaker, String text)> paragraphs, {
  required Size Function(TextItem) measure,
}) {
  const w = Drawing.a4Width, h = Drawing.a4Height;
  const s = 40.0; // renglón
  const top = s * 2.5;
  const left = s * 2 + 12; // después del margen rojo
  const width = w - left - 30;
  var id = 0;
  String nextId() => 'tr-${DateTime.now().microsecondsSinceEpoch}-${id++}';

  TextItem text(String t, {double size = 27, int color = 0xFF2B2B2B, bool bold = false}) => TextItem(
        id: nextId(),
        x: 0,
        y: 0,
        text: t,
        font: 'Patrick Hand',
        size: size,
        color: color,
        bold: bold,
        width: width,
        lineHeight: s / size, // una línea de texto por renglón
      );

  TextItem place(TextItem t, double y) {
    final sz = measure(t);
    return t.copyWith(x: left + sz.width / 2, y: y + sz.height / 2);
  }

  final pages = <List<CanvasItem>>[];
  var items = <CanvasItem>[];
  // Se escribe apoyado en el renglón: el texto empieza un poco arriba.
  var y = top - s * 0.85;
  void newPage() {
    pages.add(items);
    items = [];
    y = top - s * 0.85;
  }

  items.add(place(text(title, size: 30, bold: true, color: 0xFF8A3B22), y - s));
  for (final (at, speaker, body) in paragraphs) {
    final head = text('${formatMs(at)}${speaker == null ? '' : ' · $speaker'}', size: 22, color: 0xFF1677FF);
    final b = text(body);
    final hh = measure(head).height, bh = measure(b).height;
    if (y + hh + bh > h - s && y > top) newPage();
    items.add(place(head, y));
    y += (hh / s).ceil() * s;
    // Párrafos muy largos: se parten en otra hoja si no entran.
    if (y + bh > h - s) {
      final words = body.split(' ');
      var buf = <String>[];
      for (final word in words) {
        final tryText = text([...buf, word].join(' '));
        if (y + measure(tryText).height > h - s && buf.isNotEmpty) {
          final piece = text(buf.join(' '));
          items.add(place(piece, y));
          newPage();
          buf = [word];
        } else {
          buf.add(word);
        }
      }
      if (buf.isNotEmpty) {
        final piece = text(buf.join(' '));
        items.add(place(piece, y));
        y += (measure(piece).height / s).ceil() * s + s;
      }
    } else {
      items.add(place(b, y));
      y += (bh / s).ceil() * s + s;
    }
  }
  pages.add(items);
  return [
    for (final p in pages)
      Drawing(
        width: w,
        height: h,
        paper: const PaperStyle(template: PaperTemplate.lined),
        layers: [DrawingLayer(id: 'l1', name: 'Capa 1', items: p)],
      ),
  ];
}
