import 'dart:ui' show Size;

import '../../../core/utils/time_format.dart';
import '../../drawing/domain/canvas_item.dart';
import '../../drawing/domain/drawing.dart';
import '../../summary/domain/summary.dart';

/// Convierte un resumen en hojas Cornell A: palabras clave a la izquierda,
/// apuntes a la derecha y el resumen general abajo. Si no entra en una hoja,
/// sigue en otra. [measure] da el tamaño de un texto (en la app se usa el
/// mismo que el editor, en las pruebas uno aproximado).
List<Drawing> cornellPages(TranscriptSummary s, {required Size Function(TextItem) measure}) {
  const w = Drawing.a4Width, h = Drawing.a4Height;
  const spacing = 40.0;
  const top = spacing * 2.5; // igual que el papel
  const cueRight = w * 0.28;
  const summaryTop = h * 0.8;
  const pad = 14.0;
  var id = 0;
  String nextId() => 'cornell-${DateTime.now().microsecondsSinceEpoch}-${id++}';

  TextItem text(String t, double width, {double size = 22, bool bold = false, int color = 0xFF1F2328}) =>
      TextItem(
        id: nextId(),
        x: 0,
        y: 0,
        text: t,
        font: 'Caveat',
        size: size,
        bold: bold,
        color: color,
        width: width,
      );

  // Coloca el texto con su esquina superior izquierda en (left, topY).
  (TextItem, double) place(TextItem t, double left, double topY) {
    final sz = measure(t);
    return (t.copyWith(x: left + sz.width / 2, y: topY + sz.height / 2), sz.height);
  }

  final rows = <(String, String)>[
    for (final c in s.chapters) ('${formatMs(c.atMs)}\n${c.title}', c.summary),
    if (s.chapters.isEmpty)
      for (final k in s.keyPoints) ('Clave', k),
    if (s.chapters.isNotEmpty && s.keyPoints.isNotEmpty)
      ('Puntos clave', s.keyPoints.map((k) => '• $k').join('\n')),
    if (s.tasks.isNotEmpty)
      ('Pendientes', s.tasks.map((t) => '☐ ${t.task}${t.due != null ? ' (${t.due})' : ''}').join('\n')),
  ];

  final pages = <List<CanvasItem>>[];
  var items = <CanvasItem>[];
  var y = top;

  void newPage() {
    pages.add(items);
    items = [];
    y = top;
  }

  // Título arriba de la línea gruesa.
  final (title, _) = place(text(s.title.isEmpty ? 'Resumen' : s.title, w - 2 * pad, size: 30, bold: true),
      pad, 8);
  items.add(title);

  for (final (cue, note) in rows) {
    final c = text(cue, cueRight - 2 * pad, size: 20, bold: true, color: 0xFF8A3B22);
    final n = text(note, w - cueRight - 2 * pad);
    final rowH = [measure(c).height, measure(n).height].reduce((a, b) => a > b ? a : b) + 18;
    if (y + rowH > summaryTop - 8 && y > top) newPage();
    items
      ..add(place(c, pad, y).$1)
      ..add(place(n, cueRight + pad, y).$1);
    y += rowH;
  }

  // Resumen general en el recuadro de abajo de la primera hoja.
  if (s.overview.isNotEmpty) {
    final target = pages.isEmpty ? items : pages.first;
    target.add(place(text('Resumen: ${s.overview}', w - 2 * pad, size: 21), pad, summaryTop + 10).$1);
  }
  pages.add(items);

  return [
    for (final p in pages)
      Drawing(
        width: w,
        height: h,
        paper: const PaperStyle(template: PaperTemplate.cornell),
        layers: [DrawingLayer(id: 'l1', name: 'Capa 1', items: p)],
      ),
  ];
}
