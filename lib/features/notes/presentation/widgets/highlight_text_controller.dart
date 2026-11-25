import 'package:flutter/material.dart';

import '../../domain/note_block.dart';

/// Controlador de texto que pinta resaltados (como un marcador) y los mueve
/// solos cuando se escribe o se borra antes de ellos.
class HighlightTextController extends TextEditingController {
  HighlightTextController({super.text, List<TextMark> marks = const []})
      : _marks = [...marks],
        _last = text ?? '';

  List<TextMark> _marks;
  String _last;

  List<TextMark> get marks => List.unmodifiable(_marks);

  /// Se llama cuando los resaltados cambian (para guardarlos).
  VoidCallback? onMarksChanged;

  @override
  set value(TextEditingValue newValue) {
    final before = _last;
    super.value = newValue;
    if (newValue.text != before) {
      _shift(before, newValue.text);
      _last = newValue.text;
    }
  }

  /// Ajusta los tramos según lo que cambió (prefijo y sufijo comunes).
  void _shift(String a, String b) {
    if (_marks.isEmpty) return;
    var p = 0;
    while (p < a.length && p < b.length && a.codeUnitAt(p) == b.codeUnitAt(p)) {
      p++;
    }
    var sa = a.length, sb = b.length;
    while (sa > p && sb > p && a.codeUnitAt(sa - 1) == b.codeUnitAt(sb - 1)) {
      sa--;
      sb--;
    }
    // Se reemplazó a[p, sa) por b[p, sb).
    final delta = sb - sa;
    int map(int i, {required bool isEnd}) {
      if (i <= p) return i;
      if (i >= sa) return i + delta;
      return isEnd ? sb : p; // estaba dentro de lo reemplazado
    }

    final next = <TextMark>[];
    for (final m in _marks) {
      final s = map(m.start, isEnd: false);
      final e = map(m.end, isEnd: true);
      if (e > s) next.add(TextMark(s, e, m.color));
    }
    _marks = next;
    onMarksChanged?.call();
  }

  /// Resalta (o, con color null, quita el resaltado de) la selección.
  void highlightSelection(int? color) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final s = sel.start, e = sel.end;
    final next = <TextMark>[];
    for (final m in _marks) {
      if (m.end <= s || m.start >= e) {
        next.add(m);
        continue;
      }
      // Recortar lo que queda fuera de la selección.
      if (m.start < s) next.add(TextMark(m.start, s, m.color));
      if (m.end > e) next.add(TextMark(e, m.end, m.color));
    }
    if (color != null) next.add(TextMark(s, e, color));
    next.sort((a, b) => a.start.compareTo(b.start));
    _marks = next;
    onMarksChanged?.call();
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (_marks.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final t = text;
    final cuts = <int>{0, t.length};
    for (final m in _marks) {
      cuts.add(m.start.clamp(0, t.length));
      cuts.add(m.end.clamp(0, t.length));
    }
    final points = cuts.toList()..sort();
    final children = <TextSpan>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i], b = points[i + 1];
      if (a == b) continue;
      final mark = _marks.where((m) => m.start <= a && m.end >= b).lastOrNull;
      children.add(TextSpan(
        text: t.substring(a, b),
        style: mark == null
            ? null
            : TextStyle(backgroundColor: Color(mark.color).withValues(alpha: 0.55)),
      ));
    }
    return TextSpan(style: style, children: children);
  }
}

/// Colores de resaltador: clásicos, pastel y neón.
const highlighterColors = <int>[
  0xFFFFF176, 0xFFFFE14D, 0xFFFFCC80, 0xFFFFAB91, 0xFFF8BBD0, 0xFFF48FB1, 0xFFE1BEE7,
  0xFFCE93D8, 0xFFB3E5FC, 0xFF81D4FA, 0xFFB2DFDB, 0xFFA5D6A7, 0xFFC5E1A5, 0xFFDCEDC8,
  0xFF39FF14, 0xFFFF3EA5, 0xFF00E5FF, 0xFFFFEA00,
];
