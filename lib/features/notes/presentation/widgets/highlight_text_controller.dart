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
    newValue = _lists(before, newValue);
    super.value = newValue;
    if (newValue.text != before) {
      _shift(before, newValue.text);
      _last = newValue.text;
    }
  }

  // ------------------------------------------------------------ Listas

  static final _numbered = RegExp(r'^(\d+)\. ');

  /// Prefijo de lista de una línea ("• ", "☐ ", "☑ ", "3. ") o ''.
  static String prefixOf(String line) {
    if (line.startsWith('• ') || line.startsWith('☐ ') || line.startsWith('☑ ')) {
      return line.substring(0, 2);
    }
    final m = _numbered.firstMatch(line);
    return m?.group(0) ?? '';
  }

  static int _lineStart(String t, int i) {
    final k = t.lastIndexOf('\n', i - 1);
    return k < 0 ? 0 : k + 1;
  }

  static int _lineEnd(String t, int i) {
    final k = t.indexOf('\n', i);
    return k < 0 ? t.length : k;
  }

  /// Continúa la lista al presionar Enter y marca/desmarca casillas al
  /// tocarlas.
  TextEditingValue _lists(String before, TextEditingValue v) {
    final t = v.text;
    final sel = v.selection;
    // Enter al final de una línea de lista.
    if (t.length == before.length + 1 && sel.isCollapsed && sel.start > 0 && t[sel.start - 1] == '\n') {
      final nl = sel.start - 1;
      final prevStart = _lineStart(t, nl);
      final prevLine = t.substring(prevStart, nl);
      final prefix = prefixOf(prevLine);
      if (prefix.isNotEmpty) {
        if (prevLine.trim() == prefix.trim()) {
          // Línea vacía de lista: se termina la lista.
          final nt = t.substring(0, prevStart) + t.substring(sel.start);
          return TextEditingValue(text: nt, selection: TextSelection.collapsed(offset: prevStart));
        }
        var next = prefix == '☑ ' ? '☐ ' : prefix;
        final m = _numbered.firstMatch(prefix);
        if (m != null) next = '${int.parse(m.group(1)!) + 1}. ';
        final nt = t.substring(0, sel.start) + next + t.substring(sel.start);
        return TextEditingValue(text: nt, selection: TextSelection.collapsed(offset: sel.start + next.length));
      }
    }
    // Tocar una casilla (cursor justo antes o después de ☐/☑).
    if (t == before && sel.isCollapsed && t.isNotEmpty) {
      final start = _lineStart(t, sel.start);
      if ((sel.start == start || sel.start == start + 1) && start < t.length) {
        final ch = t[start];
        if ((ch == '☐' || ch == '☑') && start + 1 < t.length && t[start + 1] == ' ') {
          final nt = t.replaceRange(start, start + 1, ch == '☐' ? '☑' : '☐');
          return TextEditingValue(
              text: nt, selection: TextSelection.collapsed(offset: _lineEnd(nt, start)));
        }
      }
    }
    return v;
  }

  /// Pone o quita viñetas ("bullet"), casillas ("check") o números
  /// ("number") en las líneas seleccionadas.
  void toggleList(String kind) {
    final t = text;
    final sel = selection.isValid ? selection : TextSelection.collapsed(offset: t.length);
    final a = _lineStart(t, sel.start), b = _lineEnd(t, sel.end);
    final lines = t.substring(a, b).split('\n');
    bool has(String l) => switch (kind) {
          'bullet' => l.startsWith('• '),
          'check' => l.startsWith('☐ ') || l.startsWith('☑ '),
          _ => _numbered.hasMatch(l),
        };
    final remove = lines.every(has);
    var n = 0;
    final out = [
      for (final l in lines)
        () {
          final body = l.substring(prefixOf(l).length);
          if (remove) return body;
          n++;
          return switch (kind) {
                'bullet' => '• ',
                'check' => '☐ ',
                _ => '$n. ',
              } +
              body;
        }(),
    ].join('\n');
    final nt = t.replaceRange(a, b, out);
    value = TextEditingValue(text: nt, selection: TextSelection.collapsed(offset: a + out.length));
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
    final t = text;
    // Líneas marcadas (☑) se ven tachadas y en gris.
    final done = <(int, int)>[];
    var i = 0;
    while (i <= t.length) {
      final e = _lineEnd(t, i);
      if (t.startsWith('☑ ', i)) done.add((i, e));
      i = e + 1;
    }
    if (_marks.isEmpty && done.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final cuts = <int>{0, t.length};
    for (final m in _marks) {
      cuts.add(m.start.clamp(0, t.length));
      cuts.add(m.end.clamp(0, t.length));
    }
    for (final (a, b) in done) {
      cuts.add(a);
      cuts.add(b);
    }
    final points = cuts.toList()..sort();
    final children = <TextSpan>[];
    for (var k = 0; k + 1 < points.length; k++) {
      final a = points[k], b = points[k + 1];
      if (a == b) continue;
      final mark = _marks.where((m) => m.start <= a && m.end >= b).lastOrNull;
      final checked = done.any((d) => d.$1 <= a && d.$2 >= b);
      children.add(TextSpan(
        text: t.substring(a, b),
        style: TextStyle(
          backgroundColor: mark == null ? null : Color(mark.color).withValues(alpha: 0.55),
          decoration: checked ? TextDecoration.lineThrough : null,
          color: checked ? Colors.black45 : null,
        ),
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
