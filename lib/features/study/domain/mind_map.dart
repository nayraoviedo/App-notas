import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../../drawing/domain/canvas_item.dart';
import '../../drawing/domain/drawing.dart';
import '../../summary/domain/summary.dart';

/// Colores de las ramas (relleno pastel, borde y línea más oscuros).
const _branchColors = [
  (0xFFFFE0E6, 0xFFE07A93),
  (0xFFFFEBD2, 0xFFE09A4F),
  (0xFFFFF6C7, 0xFFC9A227),
  (0xFFDFF3D8, 0xFF6BAA5B),
  (0xFFD9ECFB, 0xFF4F8FC9),
  (0xFFEADFFB, 0xFF8F6BC9),
  (0xFFD8F3F0, 0xFF3FA399),
  (0xFFF6DDF1, 0xFFC25FA8),
];

String _short(String s, int max) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  // Primera oración, o recortado en una palabra.
  final dot = t.indexOf(RegExp(r'[.!?](\s|$)'));
  final first = dot > 20 && dot < max ? t.substring(0, dot + 1) : t;
  if (first.length <= max) return first;
  final cut = first.substring(0, max);
  final sp = cut.lastIndexOf(' ');
  return '${cut.substring(0, sp > 20 ? sp : max)}…';
}

/// Mapa mental de una clase en un lienzo infinito libre: el título al
/// centro, una rama por capítulo (o punto clave) y, más afuera, una idea de
/// cada capítulo. Todo es editable después (figuras, textos y líneas).
Drawing mindMapDrawing(
  TranscriptSummary s, {
  required Size Function(TextItem) measure,
  String font = 'Patrick Hand',
}) {
  var n = 0;
  String id() => 'mm${DateTime.now().microsecondsSinceEpoch}-${n++}';

  final branches = <(String title, String? leaf)>[
    if (s.chapters.isNotEmpty)
      for (final c in s.chapters.take(8)) (_short(c.title, 48), c.summary.trim().isEmpty ? null : _short(c.summary, 90))
    else
      for (final k in s.keyPoints.take(8)) (_short(k, 60), null),
  ];

  const r1 = 620.0, r2 = 1120.0;
  final size = (r2 + 700) * 2;
  final c = Offset(size / 2, size / 2);
  final items = <CanvasItem>[];
  final strokes = <Stroke>[];

  // Un "globo": figura con relleno y el texto encima.
  void node(Offset at, String text, {required double fontSize, required double maxW, required int fill, required int border, bool bold = false, ShapeKind shape = ShapeKind.roundedRect}) {
    final t = TextItem(
      id: id(),
      x: at.dx,
      y: at.dy,
      text: text,
      font: font,
      size: fontSize,
      bold: bold,
      color: 0xFF2B2B2B,
      width: maxW,
      align: TextItemAlign.center,
    );
    final m = measure(t);
    items.add(ShapeItem(
      id: id(),
      x: at.dx,
      y: at.dy,
      shape: shape,
      width: m.width + fontSize * 1.6,
      height: m.height + fontSize * 1.1,
      color: border,
      strokeWidth: 4,
      fill: fill,
    ));
    items.add(t);
  }

  // Línea curva suave de a hacia b (como rama dibujada a mano).
  void link(Offset a, Offset b, int color, double width) {
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final d = b - a;
    final ctrl = mid + Offset(-d.dy, d.dx) * 0.12;
    final pts = <StrokePoint>[];
    for (var i = 0; i <= 24; i++) {
      final t = i / 24;
      final p = a * ((1 - t) * (1 - t)) + ctrl * (2 * (1 - t) * t) + b * (t * t);
      pts.add(StrokePoint(p.dx, p.dy));
    }
    strokes.add(Stroke(tool: ToolType.marker, color: color, size: width, points: pts));
  }

  final count = math.max(1, branches.length);
  for (var i = 0; i < branches.length; i++) {
    final (title, leaf) = branches[i];
    final (fill, border) = _branchColors[i % _branchColors.length];
    // Empezar arriba y repartir en círculo.
    final a = -math.pi / 2 + i * 2 * math.pi / count;
    final dir = Offset(math.cos(a), math.sin(a));
    final b = c + dir * r1;
    link(c, b, border, 14);
    node(b, title, fontSize: 34, maxW: 360, fill: fill, border: border, bold: true);
    if (leaf != null) {
      final l = c + dir * r2;
      link(b + dir * 90, l - dir * 70, border, 7);
      node(l, leaf, fontSize: 26, maxW: 380, fill: 0xFFFFFFFF, border: border);
    }
  }
  // El centro, al final para que quede encima de las líneas.
  node(c, s.title.trim().isEmpty ? 'Clase' : _short(s.title, 60),
      fontSize: 46, maxW: 460, fill: 0xFFFFF3B0, border: 0xFF8A6D1F, bold: true, shape: ShapeKind.ellipse);

  return Drawing(
    width: size,
    height: size,
    paper: const PaperStyle(template: PaperTemplate.dots),
    infinite: true,
    grow: InfiniteGrow.both,
    // Las ramas en una capa de abajo y los globos encima, para que las
    // líneas no tapen el texto.
    layers: [
      DrawingLayer(id: 'l1', name: 'Ramas', strokes: strokes),
      DrawingLayer(id: 'l2', name: 'Ideas', items: items),
    ],
  );
}
