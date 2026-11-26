import 'dart:ui' show Rect;

import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as mlkit;

import '../domain/drawing.dart';
import '../../../core/platform_info.dart';

/// Reconocer letra a mano (ML Kit de Google, en el teléfono). El modelo de
/// español (~20 MB) se baja una sola vez.
class Handwriting {
  Handwriting._();
  static final instance = Handwriting._();

  static const lang = 'es';
  final _models = mlkit.DigitalInkRecognizerModelManager();
  mlkit.DigitalInkRecognizer? _rec;

  Future<bool> isReady() async => isPhone && await _models.isModelDownloaded(lang);

  /// Baja el modelo si falta (también con datos móviles).
  Future<void> ensureModel() async {
    if (!isPhone) throw const HandwritingException('Pasar la letra a texto solo funciona en el celular por ahora.');
    if (await _models.isModelDownloaded(lang)) return;
    final ok = await _models.downloadModel(lang, isWifiRequired: false);
    if (!ok) throw const HandwritingException('No se pudo bajar el reconocedor de letra. ¿Hay internet?');
  }

  /// Texto escrito con estos trazos (un renglón por línea).
  Future<String> recognize(List<Stroke> strokes) async {
    final writing = strokes.where((s) => s.tool != ToolType.highlighter && s.tool != ToolType.tape && s.points.length > 1).toList();
    if (writing.isEmpty) return '';
    await ensureModel();
    final rec = _rec ??= mlkit.DigitalInkRecognizer(languageCode: lang);
    final out = <String>[];
    for (final line in groupLines(writing)) {
      final ink = mlkit.Ink();
      var t = 0;
      for (final s in line) {
        final st = mlkit.Stroke();
        for (final p in s.points) {
          st.points.add(mlkit.StrokePoint(x: p.x, y: p.y, t: t));
          t += 8;
        }
        ink.strokes.add(st);
        t += 120; // pausa entre trazos
      }
      final cands = await rec.recognize(ink);
      if (cands.isNotEmpty && cands.first.text.trim().isNotEmpty) out.add(cands.first.text.trim());
    }
    return out.join('\n');
  }

  Future<void> close() async {
    await _rec?.close();
    _rec = null;
  }
}

/// Agrupa los trazos en renglones (de arriba a abajo, y cada renglón de
/// izquierda a derecha): un trazo va al renglón con el que más se superpone
/// en altura.
List<List<Stroke>> groupLines(List<Stroke> strokes) {
  final sorted = [...strokes]..sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));
  final lines = <(Rect, List<Stroke>)>[];
  for (final s in sorted) {
    final b = s.bounds;
    var best = -1;
    var bestOverlap = 0.0;
    for (final (i, (r, _)) in lines.indexed) {
      final overlap = (b.bottom < r.bottom ? b.bottom : r.bottom) - (b.top > r.top ? b.top : r.top);
      final minH = (b.height < r.height ? b.height : r.height).clamp(1.0, double.infinity);
      final ratio = overlap / minH;
      if (ratio > 0.35 && ratio > bestOverlap) {
        best = i;
        bestOverlap = ratio;
      }
    }
    if (best < 0) {
      lines.add((b, [s]));
    } else {
      final (r, list) = lines[best];
      lines[best] = (r.expandToInclude(b), [...list, s]);
    }
  }
  lines.sort((a, b) => a.$1.top.compareTo(b.$1.top));
  return [
    for (final (_, l) in lines) l..sort((a, b) => a.bounds.left.compareTo(b.bounds.left)),
  ];
}

class HandwritingException implements Exception {
  const HandwritingException(this.message);
  final String message;
  @override
  String toString() => message;
}
