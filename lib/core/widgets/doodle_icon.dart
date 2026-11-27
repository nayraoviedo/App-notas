import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Íconos "doodle" de Kumo: dibujitos hechos a mano (trazo café doble, un
/// poco tembloroso, y relleno pastel corrido, como los stickers Doodles).
/// Reemplazan a los emojis en toda la app.
///
/// Cada doodle tiene como nombre el emoji que reemplaza ('🚌', '📚'…), así
/// los datos guardados (categorías, hábitos, portadas) siguen funcionando.
///
/// - [DoodleIcon]: un doodle suelto.
/// - [DoodleText]: como `Text`, pero cambia los emojis conocidos por doodles.
/// - [hasDoodle]: si hay doodle para ese emoji.

const _inkLight = Color(0xFF3B2A22);
const _inkDark = Color(0xFFF3E6D8);
const _pink = Color(0xFFF7B6C8);
const _yellow = Color(0xFFFFE08A);
const _blue = Color(0xFFB8D8F2);
const _green = Color(0xFFBFE3B4);
const _orange = Color(0xFFF9C99A);
const _lilac = Color(0xFFD9C6F2);
const _red = Color(0xFFF4A3A3);
const _brown = Color(0xFFD7B98E);
const _gray = Color(0xFFDCE1E6);
const _white = Color(0xFFFFFFFF);

/// Quita el selector de variante (U+FE0F) para buscar el doodle.
String _key(String e) => e.replaceAll('️', '');

/// Si hay doodle para [emoji].
bool hasDoodle(String emoji) => _doodles.containsKey(_key(emoji));

/// Emojis que tienen doodle (para elegir en categorías, hábitos…).
Iterable<String> get doodleKeys => _doodles.keys;

/// Un doodle de [size] × [size]. Si no hay doodle para [emoji], muestra el
/// emoji tal cual (por ejemplo, uno que la persona escribió).
class DoodleIcon extends StatelessWidget {
  const DoodleIcon(this.emoji, {super.key, this.size = 24, this.semanticLabel});
  final String emoji;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final draw = _doodles[_key(emoji)];
    if (draw == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: Text(emoji, style: TextStyle(fontSize: size * 0.8, height: 1))),
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: DoodlePainter(emoji, ink: dark ? _inkDark : _inkLight)),
      ),
    );
  }
}

/// Pinta el doodle de [emoji] (sirve también para PNG o PDF).
class DoodlePainter extends CustomPainter {
  DoodlePainter(this.emoji, {this.ink = _inkLight});
  final String emoji;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final draw = _doodles[_key(emoji)];
    if (draw == null) return;
    final k = math.min(size.width, size.height) / 100;
    canvas.save();
    canvas.translate((size.width - 100 * k) / 2, (size.height - 100 * k) / 2);
    canvas.scale(k);
    // En tamaños chicos el trazo se engrosa para que se lea.
    draw(_D(canvas, ink, math.max(5.0, 1.6 / k)));
    canvas.restore();
  }

  @override
  bool shouldRepaint(DoodlePainter old) => old.emoji != emoji || old.ink != ink;
}

/// `Text` que cambia los emojis conocidos por doodles del mismo tamaño que la letra.
class DoodleText extends StatelessWidget {
  const DoodleText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    return Text.rich(
      TextSpan(children: doodleSpans(text, base)),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
  }
}

/// Parte [text] en trozos de texto y doodles (para usar en `Text.rich`).
List<InlineSpan> doodleSpans(String text, TextStyle style) {
  final size = (style.fontSize ?? 14) * 1.25;
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in _pattern.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: DoodleIcon(m.group(0)!, size: size),
    ));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

/// Quita los emojis que tienen doodle (para textos que no pueden mostrar
/// dibujos, como los avisos del sistema).
String stripDoodles(String text) =>
    text.replaceAll(_pattern, '').replaceAll(RegExp(r'  +'), ' ').trim();

final RegExp _pattern = () {
  final keys = _doodles.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  return RegExp('(?:${keys.map(RegExp.escape).join('|')})️?');
}();

// ------------------------------------------------------------------ Pincel

/// Pincel de doodles: cada trazo lleva relleno corrido + trazo doble a mano.
class _D {
  _D(this.c, this.ink, this.stroke);
  final Canvas c;
  final Color ink;
  final double stroke;

  /// Dibuja [p] con relleno [fill] (opcional). [w] multiplica el grosor.
  void call(Path p, {Color? fill, double w = 1, bool line = true}) {
    if (fill != null) {
      c.save();
      c.translate(2.6, 2.8); // relleno un poco corrido
      c.drawPath(p, Paint()..color = fill);
      c.restore();
    }
    if (!line) return;
    final paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    c.drawPath(p, paint);
    c.save();
    c.translate(0.9, -0.7); // segunda pasada: parece lápiz
    c.drawPath(p, paint..color = ink.withValues(alpha: 0.3)..strokeWidth = stroke * w * 0.5);
    c.restore();
  }

  /// Puntos rellenos (ojos, semillas…).
  void dots(List<Offset> pts, double r) {
    final paint = Paint()..color = ink;
    for (final o in pts) {
      c.drawCircle(o, r, paint);
    }
  }
}

Path _circle(double x, double y, double r) => Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
Path _oval(double l, double t, double r, double b) => Path()..addOval(Rect.fromLTRB(l, t, r, b));
Path _rrect(double l, double t, double r, double b, double rad) =>
    Path()..addRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(rad)));
Path _poly(List<double> xy, {bool close = true}) {
  final p = Path()..moveTo(xy[0], xy[1]);
  for (var i = 2; i < xy.length; i += 2) {
    p.lineTo(xy[i], xy[i + 1]);
  }
  if (close) p.close();
  return p;
}

/// Varios segmentos sueltos: [x1, y1, x2, y2, …] de a cuatro.
Path _lines(List<double> v) {
  final p = Path();
  for (var i = 0; i < v.length; i += 4) {
    p
      ..moveTo(v[i], v[i + 1])
      ..lineTo(v[i + 2], v[i + 3]);
  }
  return p;
}

Path _star(double cx, double cy, double r, {int points = 5, double inner = 0.45}) {
  final p = Path();
  for (var i = 0; i < points * 2; i++) {
    final rr = i.isEven ? r : r * inner;
    final a = -math.pi / 2 + i * math.pi / points;
    final x = cx + rr * math.cos(a), y = cy + rr * math.sin(a);
    i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
  }
  return p..close();
}

Path _sparkle(double cx, double cy, double r) => Path()
  ..moveTo(cx, cy - r)
  ..quadraticBezierTo(cx + r * 0.12, cy - r * 0.12, cx + r, cy)
  ..quadraticBezierTo(cx + r * 0.12, cy + r * 0.12, cx, cy + r)
  ..quadraticBezierTo(cx - r * 0.12, cy + r * 0.12, cx - r, cy)
  ..quadraticBezierTo(cx - r * 0.12, cy - r * 0.12, cx, cy - r)
  ..close();

Path _heart(double dx, double dy, double k) {
  final p = Path()
    ..moveTo(50, 86)
    ..cubicTo(18, 64, 8, 44, 16, 28)
    ..cubicTo(24, 12, 44, 14, 50, 32)
    ..cubicTo(57, 13, 78, 11, 86, 28)
    ..cubicTo(94, 46, 80, 65, 50, 86)
    ..close();
  return p.transform((Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(k, k, 1, 1))
      .storage);
}

Path _cloud(double dx, double dy, double k) {
  final p = Path()
    ..moveTo(22, 70)
    ..cubicTo(8, 70, 8, 50, 22, 50)
    ..cubicTo(20, 34, 40, 28, 48, 38)
    ..cubicTo(54, 22, 80, 24, 80, 44)
    ..cubicTo(96, 44, 96, 70, 80, 70)
    ..close();
  return p.transform((Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(k, k, 1, 1))
      .storage);
}

/// Carita redonda con [fill]; [features] dibuja ojos y boca.
void _face(_D d, Color fill, void Function() features) {
  d(_circle(50, 52, 40), fill: fill);
  features();
}

void _sun(_D d, double cx, double cy, double r) {
  d(_circle(cx, cy, r), fill: _yellow);
  final p = Path();
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi / 4;
    p
      ..moveTo(cx + (r + 7) * math.cos(a), cy + (r + 7) * math.sin(a))
      ..lineTo(cx + (r + 16) * math.cos(a), cy + (r + 16) * math.sin(a));
  }
  d(p);
}

// ----------------------------------------------------------------- Doodles

final Map<String, void Function(_D d)> _doodles = {
  for (final e in _raw.entries) _key(e.key): e.value,
};

final Map<String, void Function(_D d)> _raw = {
  // ---------------------------------------------------------- Comida
  '🥬': (d) {
    d(Path()
      ..moveTo(50, 92)
      ..cubicTo(20, 86, 10, 56, 22, 34)
      ..cubicTo(26, 16, 44, 8, 52, 18)
      ..cubicTo(64, 6, 86, 16, 82, 36)
      ..cubicTo(94, 58, 80, 86, 50, 92)
      ..close(), fill: _green);
    d(Path()
      ..moveTo(50, 90)
      ..cubicTo(48, 66, 52, 44, 52, 22)
      ..moveTo(50, 64)
      ..lineTo(34, 48)
      ..moveTo(51, 48)
      ..lineTo(66, 36)
      ..moveTo(50, 76)
      ..lineTo(66, 62), w: 0.8);
  },
  '🍎': (d) {
    d(Path()
      ..moveTo(50, 32)
      ..cubicTo(30, 18, 8, 34, 14, 60)
      ..cubicTo(20, 86, 40, 94, 50, 86)
      ..cubicTo(60, 94, 80, 86, 86, 60)
      ..cubicTo(92, 34, 70, 18, 50, 32)
      ..close(), fill: _red);
    d(Path()
      ..moveTo(50, 32)
      ..cubicTo(50, 22, 52, 14, 56, 8));
    d(Path()
      ..moveTo(56, 20)
      ..cubicTo(64, 8, 78, 10, 80, 14)
      ..cubicTo(74, 24, 62, 26, 56, 20)
      ..close(), fill: _green);
    d(Path()
      ..moveTo(28, 48)
      ..cubicTo(26, 54, 26, 58, 28, 62), w: 0.7);
  },
  '🥩': (d) {
    // Bistec con su hueso.
    d(Path()
      ..moveTo(14, 46)
      ..cubicTo(10, 20, 50, 8, 74, 20)
      ..cubicTo(94, 30, 94, 58, 78, 70)
      ..cubicTo(64, 80, 58, 92, 40, 88)
      ..cubicTo(20, 84, 18, 66, 14, 46)
      ..close(), fill: _red);
    d(Path()
      ..moveTo(22, 46)
      ..cubicTo(20, 28, 50, 18, 70, 26), w: 0.7);
    d(_circle(62, 52, 9), fill: _white, w: 0.8);
    d(Path()
      ..moveTo(30, 60)
      ..cubicTo(36, 56, 40, 64, 46, 60), w: 0.6);
  },
  '🍚': (d) {
    d(Path()
      ..moveTo(14, 46)
      ..cubicTo(14, 22, 86, 22, 86, 46)
      ..close(), fill: _white);
    d(Path()
      ..moveTo(8, 46)
      ..lineTo(92, 46)
      ..cubicTo(90, 72, 72, 84, 50, 84)
      ..cubicTo(28, 84, 10, 72, 8, 46)
      ..close(), fill: _blue);
    d(_lines([36, 84, 36, 92, 64, 84, 64, 92, 30, 92, 70, 92]));
    d(_lines([34, 36, 38, 34, 50, 30, 54, 32, 62, 38, 66, 36]), w: 0.7);
  },
  '🥛': (d) {
    d(_poly([24, 12, 76, 12, 68, 92, 32, 92]), fill: _white);
    d(Path()
      ..moveTo(27, 38)
      ..cubicTo(40, 32, 58, 44, 73, 38), w: 0.8);
    d(_poly([28, 42, 72, 42, 68, 92, 32, 92]), fill: _blue, line: false);
  },
  '🍞': (d) {
    d(Path()
      ..moveTo(24, 92)
      ..lineTo(24, 46)
      ..cubicTo(6, 44, 6, 12, 30, 12)
      ..lineTo(70, 12)
      ..cubicTo(94, 12, 94, 44, 76, 46)
      ..lineTo(76, 92)
      ..close(), fill: _brown);
    d(Path()
      ..moveTo(32, 86)
      ..lineTo(32, 42)
      ..cubicTo(20, 40, 18, 22, 34, 20)
      ..lineTo(66, 20)
      ..cubicTo(82, 22, 80, 40, 68, 42)
      ..lineTo(68, 86)
      ..close(), fill: _yellow, w: 0.6);
  },
  '🐟': (d) {
    d(Path()
      ..moveTo(12, 50)
      ..cubicTo(28, 24, 60, 22, 74, 50)
      ..cubicTo(60, 78, 28, 76, 12, 50)
      ..close(), fill: _blue);
    d(_poly([72, 50, 92, 32, 88, 50, 92, 68]), fill: _blue);
    d.dots([const Offset(28, 46)], 3.5);
    d(Path()
      ..moveTo(44, 36)
      ..cubicTo(50, 44, 50, 56, 44, 64), w: 0.7);
  },
  '🥚': (d) {
    d(Path()
      ..moveTo(50, 8)
      ..cubicTo(76, 8, 88, 54, 82, 70)
      ..cubicTo(76, 88, 24, 88, 18, 70)
      ..cubicTo(12, 54, 24, 8, 50, 8)
      ..close(), fill: _white);
    d(_circle(50, 60, 14), fill: _yellow, w: 0.7);
  },
  '🧃': (d) {
    d(_rrect(24, 26, 72, 92, 4), fill: _orange);
    d(_poly([24, 26, 34, 14, 82, 14, 72, 26]), fill: _yellow);
    d(_poly([72, 26, 82, 14, 82, 80, 72, 92], close: false));
    d(_lines([58, 14, 62, 2, 62, 2, 72, 2]));
    d(_circle(48, 60, 12), fill: _green, w: 0.7);
  },
  '🍬': (d) {
    d(_circle(50, 50, 20), fill: _pink);
    d(_poly([30, 50, 10, 34, 12, 66]), fill: _yellow);
    d(_poly([70, 50, 90, 34, 88, 66]), fill: _yellow);
    d(Path()
      ..moveTo(40, 36)
      ..cubicTo(46, 46, 46, 56, 40, 64)
      ..moveTo(54, 32)
      ..cubicTo(60, 44, 60, 56, 54, 68), w: 0.7);
  },
  '🍲': (d) {
    d(Path()
      ..moveTo(10, 44)
      ..lineTo(90, 44)
      ..cubicTo(88, 74, 72, 86, 50, 86)
      ..cubicTo(28, 86, 12, 74, 10, 44)
      ..close(), fill: _orange);
    d(_lines([4, 44, 96, 44]));
    d(Path()
      ..moveTo(34, 34)
      ..cubicTo(28, 26, 40, 20, 34, 10)
      ..moveTo(50, 34)
      ..cubicTo(44, 26, 56, 20, 50, 10)
      ..moveTo(66, 34)
      ..cubicTo(60, 26, 72, 20, 66, 10), w: 0.8);
    d(_circle(36, 58, 5), fill: _green, w: 0.6);
    d(_circle(60, 62, 5), fill: _red, w: 0.6);
  },
  '🥗': (d) {
    d(Path()
      ..moveTo(28, 46)
      ..cubicTo(24, 26, 44, 22, 48, 34)
      ..cubicTo(52, 18, 76, 22, 72, 46)
      ..close(), fill: _green);
    d(_circle(60, 40, 6), fill: _red, w: 0.6);
    d(Path()
      ..moveTo(8, 46)
      ..lineTo(92, 46)
      ..cubicTo(90, 72, 72, 86, 50, 86)
      ..cubicTo(28, 86, 10, 72, 8, 46)
      ..close(), fill: _white);
  },
  '☕': (d) {
    d(Path()
      ..moveTo(16, 40)
      ..lineTo(72, 40)
      ..lineTo(68, 84)
      ..quadraticBezierTo(44, 92, 20, 84)
      ..close(), fill: _orange);
    d(Path()
      ..moveTo(71, 50)
      ..cubicTo(92, 46, 92, 74, 69, 72)
      ..moveTo(34, 30)
      ..cubicTo(28, 22, 40, 18, 34, 8)
      ..moveTo(52, 30)
      ..cubicTo(46, 22, 58, 18, 52, 8));
  },
  '🍅': (d) {
    d(_circle(50, 56, 34), fill: _red);
    d(_star(50, 26, 14, points: 5, inner: 0.4), fill: _green, w: 0.8);
  },
  '🍰': (d) {
    d(_poly([12, 50, 88, 40, 88, 84, 12, 88]), fill: _yellow);
    d(Path()
      ..moveTo(12, 50)
      ..cubicTo(30, 30, 60, 26, 88, 40), fill: _pink);
    d(_lines([12, 66, 88, 62]), w: 0.8);
    d(_circle(56, 24, 7), fill: _red, w: 0.8);
  },

  // ----------------------------------------------------- Casa y cosas
  '🧼': (d) {
    d(_rrect(12, 42, 88, 86, 16), fill: _pink);
    d(_circle(30, 26, 9), fill: _blue, w: 0.8);
    d(_circle(52, 18, 6), fill: _blue, w: 0.8);
    d(_circle(68, 30, 7), fill: _blue, w: 0.8);
    d(_lines([28, 58, 60, 58]), w: 0.8);
  },
  '🛍️': (d) {
    d(_poly([14, 34, 86, 34, 92, 92, 8, 92]), fill: _pink);
    d(Path()
      ..moveTo(34, 46)
      ..lineTo(34, 24)
      ..cubicTo(34, 4, 66, 4, 66, 24)
      ..lineTo(66, 46));
    d.dots([const Offset(34, 48), const Offset(66, 48)], 3);
  },
  '🛒': (d) {
    d(_poly([22, 28, 90, 28, 82, 64, 30, 64]), fill: _yellow);
    d(Path()
      ..moveTo(4, 14)
      ..lineTo(18, 14)
      ..lineTo(30, 64)
      ..lineTo(28, 74)
      ..lineTo(84, 74));
    d(_circle(36, 86, 6), fill: _white);
    d(_circle(76, 86, 6), fill: _white);
    d(_lines([44, 28, 46, 64, 64, 28, 62, 64]), w: 0.7);
  },
  '💊': (d) {
    final r = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-38, -16, 76, 32), const Radius.circular(16)));
    final m = (Matrix4.identity()
          ..translateByDouble(50, 50, 0, 1)
          ..rotateZ(-math.pi / 4))
        .storage;
    d(r.transform(m), fill: _white);
    final half = Path()
      ..moveTo(0, -16)
      ..lineTo(22, -16)
      ..arcToPoint(const Offset(22, 16), radius: const Radius.circular(16))
      ..lineTo(0, 16)
      ..close();
    d(half.transform(m), fill: _pink);
  },
  '🚌': (d) {
    d(_rrect(12, 14, 88, 80, 12), fill: _yellow);
    d(_rrect(20, 24, 80, 50, 5), fill: _blue, w: 0.8);
    d(_lines([50, 24, 50, 50]), w: 0.7);
    d(_lines([18, 66, 30, 66, 70, 66, 82, 66]), w: 0.9);
    d(_circle(30, 86, 7), fill: _white);
    d(_circle(70, 86, 7), fill: _white);
  },
  '🏠': (d) {
    d(_poly([18, 48, 18, 90, 82, 90, 82, 48]), fill: _orange);
    d(_poly([8, 52, 50, 12, 92, 52]), fill: _red);
    d(_rrect(42, 64, 58, 90, 3), fill: _brown, w: 0.8);
    d(_rrect(64, 58, 76, 70, 2), fill: _blue, w: 0.7);
  },
  '📚': (d) {
    d(_rrect(10, 72, 86, 90, 3), fill: _blue);
    d(_rrect(16, 54, 80, 72, 3), fill: _pink);
    d(_rrect(10, 36, 84, 54, 3), fill: _green);
    d(_lines([70, 72, 70, 90, 26, 54, 26, 72, 68, 36, 68, 54]), w: 0.7);
    d(Path()
      ..moveTo(28, 36)
      ..lineTo(36, 10)
      ..lineTo(56, 14)
      ..lineTo(50, 36), fill: _yellow);
  },
  '🎁': (d) {
    d(_rrect(12, 38, 88, 54, 3), fill: _pink);
    d(_rrect(18, 54, 82, 92, 3), fill: _pink);
    d(_lines([50, 38, 50, 92]), w: 1.1);
    d(Path()
      ..moveTo(50, 38)
      ..cubicTo(36, 12, 18, 24, 30, 36)
      ..moveTo(50, 38)
      ..cubicTo(64, 12, 82, 24, 70, 36));
  },
  '📄': (d) {
    d(_poly([20, 8, 64, 8, 82, 26, 82, 92, 20, 92]), fill: _white);
    d(_poly([64, 8, 64, 26, 82, 26], close: false));
    d(_lines([32, 40, 70, 40, 32, 54, 70, 54, 32, 68, 58, 68]), w: 0.7);
  },
  '🖨️': (d) {
    d(_rrect(28, 8, 72, 34, 2), fill: _white);
    d(_rrect(8, 34, 92, 72, 8), fill: _gray);
    d(_rrect(26, 60, 74, 94, 2), fill: _white);
    d(_lines([36, 72, 64, 72, 36, 82, 56, 82]), w: 0.7);
    d.dots([const Offset(80, 46)], 3.5);
  },
  '✏️': (d) {
    final m = (Matrix4.identity()
          ..translateByDouble(50, 50, 0, 1)
          ..rotateZ(-math.pi / 4))
        .storage;
    d(_poly([-44, 0, -28, -11, 40, -11, 40, 11, -28, 11]).transform(m), fill: _yellow);
    d(_poly([40, -11, 48, -11, 48, 11, 40, 11]).transform(m), fill: _pink);
    d(_lines([-28, -11, -28, 11]).transform(m));
    d(_poly([-44, 0, -37, -5, -37, 5]).transform(m), fill: _inkLight, w: 0.6);
  },
  '✍️': (d) {
    final m = (Matrix4.identity()
          ..translateByDouble(54, 42, 0, 1)
          ..rotateZ(-math.pi / 4))
        .storage;
    d(_poly([-40, 0, -26, -10, 34, -10, 34, 10, -26, 10]).transform(m), fill: _yellow);
    d(_lines([-26, -10, -26, 10]).transform(m));
    d(Path()
      ..moveTo(8, 88)
      ..cubicTo(16, 76, 22, 96, 30, 84)
      ..cubicTo(38, 72, 42, 94, 52, 86)
      ..lineTo(92, 86), w: 0.9);
  },
  '🎓': (d) {
    d(_poly([50, 14, 94, 34, 50, 54, 6, 34]), fill: _lilac);
    d(Path()
      ..moveTo(24, 44)
      ..lineTo(24, 66)
      ..cubicTo(36, 80, 64, 80, 76, 66)
      ..lineTo(76, 44), fill: _lilac);
    d(Path()
      ..moveTo(50, 34)
      ..lineTo(86, 44)
      ..lineTo(86, 70));
    d(_circle(86, 74, 4), fill: _yellow, w: 0.7);
  },
  '📱': (d) {
    d(_rrect(26, 6, 74, 94, 10), fill: _lilac);
    d(_rrect(32, 16, 68, 76, 3), fill: _white, w: 0.7);
    d(_lines([44, 85, 56, 85]), w: 0.9);
  },
  '👕': (d) {
    d(_poly([34, 12, 10, 26, 18, 46, 28, 42, 28, 90, 72, 90, 72, 42, 82, 46, 90, 26, 66, 12]), fill: _blue);
    d(Path()
      ..moveTo(34, 12)
      ..cubicTo(40, 26, 60, 26, 66, 12), w: 0.9);
  },
  '🧾': (d) {
    d(_poly([20, 8, 80, 8, 80, 92, 70, 84, 60, 92, 50, 84, 40, 92, 30, 84, 20, 92]), fill: _white);
    d(_lines([32, 26, 68, 26, 32, 40, 68, 40, 32, 54, 56, 54]), w: 0.7);
    d(_lines([56, 70, 68, 70]), w: 1.1);
  },
  '💰': (d) {
    d(Path()
      ..moveTo(38, 26)
      ..cubicTo(8, 40, 6, 92, 50, 92)
      ..cubicTo(94, 92, 92, 40, 62, 26)
      ..close(), fill: _yellow);
    d(_poly([36, 26, 64, 26, 72, 10, 28, 10]), fill: _yellow);
    d(Path()
      ..moveTo(58, 48)
      ..cubicTo(52, 42, 38, 44, 40, 54)
      ..cubicTo(42, 62, 60, 60, 60, 70)
      ..cubicTo(60, 80, 44, 80, 40, 74)
      ..moveTo(50, 40)
      ..lineTo(50, 84), w: 0.8);
  },
  '💸': (d) {
    d(_rrect(10, 36, 78, 76, 4), fill: _green);
    d(_circle(44, 56, 10), w: 0.8);
    d(Path()
      ..moveTo(78, 44)
      ..cubicTo(86, 34, 94, 40, 92, 30)
      ..moveTo(78, 64)
      ..cubicTo(88, 60, 94, 66, 96, 56), w: 0.8);
    d(Path()
      ..moveTo(10, 46)
      ..cubicTo(4, 30, 18, 22, 22, 36)
      ..moveTo(26, 76)
      ..cubicTo(20, 92, 36, 94, 36, 80), w: 0.8);
  },
  '📝': (d) {
    d(_poly([14, 10, 72, 10, 72, 90, 14, 90]), fill: _white);
    d(_lines([24, 30, 60, 30, 24, 46, 60, 46, 24, 62, 44, 62]), w: 0.7);
    final m = (Matrix4.identity()
          ..translateByDouble(70, 56, 0, 1)
          ..rotateZ(-math.pi / 3))
        .storage;
    d(_poly([-30, 0, -20, -7, 26, -7, 26, 7, -20, 7]).transform(m), fill: _yellow);
  },
  '📒': (d) {
    d(_rrect(18, 8, 84, 92, 6), fill: _yellow);
    d(_lines([30, 8, 30, 92]), w: 0.8);
    d(_rrect(42, 26, 74, 44, 3), fill: _white, w: 0.7);
    d.dots([const Offset(18, 24), const Offset(18, 44), const Offset(18, 64), const Offset(18, 82)], 3.5);
  },
  '📷': (d) {
    d(_rrect(8, 28, 92, 84, 10), fill: _blue);
    d(_poly([32, 28, 40, 16, 60, 16, 68, 28]), fill: _blue);
    d(_circle(50, 56, 17), fill: _white);
    d(_circle(50, 56, 8), w: 0.7);
    d.dots([const Offset(80, 40)], 3.5);
  },
  '🖼️': (d) {
    d(_rrect(8, 14, 92, 86, 4), fill: _white);
    d(_poly([16, 78, 40, 46, 56, 64, 66, 54, 84, 78]), fill: _green, w: 0.8);
    d(_circle(70, 32, 8), fill: _yellow, w: 0.8);
  },
  '🔔': (d) {
    d(Path()
      ..moveTo(50, 12)
      ..cubicTo(26, 12, 24, 36, 24, 52)
      ..cubicTo(24, 64, 16, 70, 12, 76)
      ..lineTo(88, 76)
      ..cubicTo(84, 70, 76, 64, 76, 52)
      ..cubicTo(76, 36, 74, 12, 50, 12)
      ..close(), fill: _yellow);
    d(Path()
      ..moveTo(40, 80)
      ..cubicTo(40, 94, 60, 94, 60, 80), fill: _yellow);
    d(_lines([50, 4, 50, 12]));
  },
  '⏰': (d) {
    d(_circle(50, 54, 34), fill: _white);
    d(_lines([50, 54, 50, 34, 50, 54, 64, 62]), w: 0.9);
    d(_circle(22, 22, 10), fill: _red, w: 0.8);
    d(_circle(78, 22, 10), fill: _red, w: 0.8);
    d(_lines([28, 82, 20, 92, 72, 82, 80, 92]));
  },
  '🎧': (d) {
    d(Path()
      ..moveTo(16, 62)
      ..lineTo(16, 50)
      ..cubicTo(16, 6, 84, 6, 84, 50)
      ..lineTo(84, 62));
    d(_rrect(8, 54, 30, 88, 8), fill: _pink);
    d(_rrect(70, 54, 92, 88, 8), fill: _pink);
  },
  '🎙️': (d) {
    d(_rrect(34, 6, 66, 60, 16), fill: _lilac);
    d(Path()
      ..moveTo(22, 44)
      ..cubicTo(22, 82, 78, 82, 78, 44)
      ..moveTo(50, 74)
      ..lineTo(50, 90)
      ..moveTo(34, 92)
      ..lineTo(66, 92));
    d(_lines([42, 24, 58, 24, 42, 36, 58, 36]), w: 0.6);
  },
  '🧠': (d) {
    d(Path()
      ..moveTo(50, 20)
      ..cubicTo(40, 8, 20, 14, 22, 30)
      ..cubicTo(6, 34, 6, 56, 18, 62)
      ..cubicTo(14, 78, 34, 86, 42, 78)
      ..cubicTo(46, 86, 54, 86, 58, 78)
      ..cubicTo(66, 86, 86, 78, 82, 62)
      ..cubicTo(94, 56, 94, 34, 78, 30)
      ..cubicTo(80, 14, 60, 8, 50, 20)
      ..close(), fill: _pink);
    d(Path()
      ..moveTo(50, 20)
      ..lineTo(50, 80)
      ..moveTo(22, 30)
      ..cubicTo(30, 34, 34, 40, 32, 46)
      ..moveTo(78, 30)
      ..cubicTo(70, 34, 66, 40, 68, 46)
      ..moveTo(18, 62)
      ..cubicTo(26, 58, 34, 60, 36, 66)
      ..moveTo(82, 62)
      ..cubicTo(74, 58, 66, 60, 64, 66), w: 0.7);
  },
  '💡': (d) {
    d(Path()
      ..moveTo(38, 66)
      ..cubicTo(20, 52, 22, 12, 50, 10)
      ..cubicTo(78, 12, 80, 52, 62, 66)
      ..lineTo(62, 76)
      ..lineTo(38, 76)
      ..close(), fill: _yellow);
    d(_lines([40, 84, 60, 84, 44, 92, 56, 92]));
  },
  '💪': (d) {
    d(Path()
      ..moveTo(12, 86)
      ..lineTo(18, 54)
      ..cubicTo(22, 36, 30, 26, 36, 18)
      ..cubicTo(40, 10, 52, 10, 54, 18)
      ..cubicTo(56, 24, 50, 30, 44, 32)
      ..lineTo(42, 50)
      ..cubicTo(56, 38, 84, 40, 88, 60)
      ..cubicTo(92, 80, 70, 90, 50, 88)
      ..close(), fill: _orange);
    d(Path()
      ..moveTo(50, 64)
      ..cubicTo(58, 56, 70, 58, 74, 66), w: 0.7);
  },
  '🔥': (d) {
    d(Path()
      ..moveTo(50, 92)
      ..cubicTo(22, 92, 14, 68, 22, 52)
      ..cubicTo(26, 60, 32, 62, 36, 60)
      ..cubicTo(30, 40, 40, 20, 56, 8)
      ..cubicTo(56, 26, 66, 34, 72, 44)
      ..cubicTo(76, 40, 76, 34, 74, 30)
      ..cubicTo(90, 46, 90, 92, 50, 92)
      ..close(), fill: _orange);
    d(Path()
      ..moveTo(50, 90)
      ..cubicTo(36, 90, 34, 74, 42, 64)
      ..cubicTo(46, 70, 50, 70, 52, 62)
      ..cubicTo(64, 70, 66, 90, 50, 90)
      ..close(), fill: _yellow, w: 0.7);
  },
  '⚠️': (d) {
    d(Path()
      ..moveTo(50, 10)
      ..lineTo(92, 86)
      ..lineTo(8, 86)
      ..close(), fill: _yellow);
    d(_lines([50, 36, 50, 62]), w: 1.2);
    d.dots([const Offset(50, 74)], 4.5);
  },
  '👀': (d) {
    d(_oval(8, 22, 48, 78), fill: _white);
    d(_oval(52, 22, 92, 78), fill: _white);
    d.dots([const Offset(36, 54), const Offset(80, 54)], 8);
  },
  '☁️': (d) => d(_cloud(0, -2, 1), fill: _blue),
  '✨': (d) {
    d(_sparkle(40, 56, 30), fill: _yellow);
    d(_sparkle(78, 22, 14), fill: _yellow);
    d(_sparkle(80, 80, 9));
  },
  '⭐': (d) => d(_star(50, 54, 42), fill: _yellow),
  '🌟': (d) {
    d(_star(50, 54, 38), fill: _yellow);
    d(_lines([10, 16, 18, 22, 90, 16, 82, 22, 50, 98, 50, 92]), w: 0.8);
  },
  '❤️': (d) => d(_heart(0, 0, 1), fill: _pink),
  '♡': (d) => d(_heart(0, 0, 1)),
  '💧': (d) {
    d(Path()
      ..moveTo(50, 8)
      ..cubicTo(60, 30, 80, 46, 80, 64)
      ..cubicTo(80, 82, 66, 92, 50, 92)
      ..cubicTo(34, 92, 20, 82, 20, 64)
      ..cubicTo(20, 46, 40, 30, 50, 8)
      ..close(), fill: _blue);
    d(Path()
      ..moveTo(34, 62)
      ..cubicTo(32, 70, 36, 78, 42, 80), w: 0.7);
  },
  '☀️': (d) => _sun(d, 50, 50, 22),
  '🌤️': (d) {
    _sun(d, 38, 38, 18);
    d(_cloud(28, 36, 0.66), fill: _white);
  },
  '🌙': (d) {
    d(Path()
      ..moveTo(56, 10)
      ..cubicTo(20, 14, 12, 74, 52, 88)
      ..cubicTo(70, 92, 86, 82, 90, 70)
      ..cubicTo(56, 76, 34, 44, 56, 10)
      ..close(), fill: _lilac);
    d(_sparkle(78, 26, 9));
  },
  '🌸': (d) {
    final p = Path();
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      p.addOval(Rect.fromCenter(center: Offset(50 + 22 * math.cos(a), 52 + 22 * math.sin(a)), width: 30, height: 30));
    }
    d(p, fill: _pink);
    d(_circle(50, 52, 10), fill: _yellow);
  },
  '🎨': (d) {
    d(Path()
      ..moveTo(50, 10)
      ..cubicTo(14, 10, 4, 46, 12, 66)
      ..cubicTo(20, 88, 48, 94, 60, 84)
      ..cubicTo(70, 76, 56, 66, 66, 60)
      ..cubicTo(78, 54, 92, 62, 92, 44)
      ..cubicTo(92, 24, 74, 10, 50, 10)
      ..close(), fill: _brown);
    d(_circle(30, 34, 7), fill: _red, w: 0.7);
    d(_circle(52, 26, 7), fill: _yellow, w: 0.7);
    d(_circle(72, 34, 7), fill: _blue, w: 0.7);
    d(_circle(26, 58, 7), fill: _green, w: 0.7);
  },
  '🎵': (d) {
    d(_oval(18, 66, 46, 88), fill: _inkLight);
    d(_lines([44, 76, 44, 12]));
    d(Path()
      ..moveTo(44, 12)
      ..cubicTo(60, 20, 74, 24, 72, 44), w: 1);
  },
  '🎉': (d) {
    d(_poly([10, 92, 34, 30, 72, 68]), fill: _yellow);
    d(_lines([22, 62, 42, 80, 28, 46, 54, 72]), w: 0.6);
    d(Path()
      ..moveTo(52, 38)
      ..cubicTo(56, 26, 70, 26, 66, 14)
      ..moveTo(64, 50)
      ..cubicTo(74, 46, 82, 52, 90, 44), w: 0.8);
    d(_circle(84, 22, 5), fill: _pink, w: 0.7);
    d(_sparkle(48, 12, 7));
    d(_circle(88, 66, 4), fill: _blue, w: 0.7);
  },
  '🐱': (d) {
    d(Path()
      ..moveTo(18, 46)
      ..lineTo(16, 12)
      ..lineTo(38, 30)
      ..cubicTo(46, 27, 54, 27, 62, 30)
      ..lineTo(84, 12)
      ..lineTo(82, 46)
      ..cubicTo(90, 76, 70, 88, 50, 88)
      ..cubicTo(30, 88, 10, 76, 18, 46)
      ..close(), fill: _orange);
    d.dots([const Offset(36, 56), const Offset(64, 56)], 4);
    d(Path()
      ..moveTo(44, 66)
      ..quadraticBezierTo(50, 72, 50, 64)
      ..quadraticBezierTo(50, 72, 56, 66)
      ..moveTo(4, 60)
      ..lineTo(22, 62)
      ..moveTo(96, 60)
      ..lineTo(78, 62), w: 0.7);
  },
  '🐾': (d) {
    d(Path()
      ..moveTo(50, 50)
      ..cubicTo(70, 50, 84, 74, 72, 82)
      ..cubicTo(62, 88, 56, 78, 50, 78)
      ..cubicTo(44, 78, 38, 88, 28, 82)
      ..cubicTo(16, 74, 30, 50, 50, 50)
      ..close()
      ..addOval(Rect.fromCenter(center: const Offset(20, 46), width: 14, height: 18))
      ..addOval(Rect.fromCenter(center: const Offset(36, 28), width: 14, height: 18))
      ..addOval(Rect.fromCenter(center: const Offset(64, 28), width: 14, height: 18))
      ..addOval(Rect.fromCenter(center: const Offset(80, 46), width: 14, height: 18)), fill: _pink);
  },
  '🧹': (d) {
    d(_lines([72, 6, 50, 52]));
    d(Path()
      ..moveTo(36, 46)
      ..lineTo(64, 58)
      ..lineTo(58, 94)
      ..lineTo(10, 74)
      ..close(), fill: _yellow);
    d(_lines([30, 64, 20, 80, 42, 70, 32, 88, 54, 74, 48, 92]), w: 0.6);
  },
  '🏃‍♀️': (d) {
    // Zapatilla de correr.
    d(Path()
      ..moveTo(10, 72)
      ..lineTo(12, 40)
      ..cubicTo(24, 42, 34, 40, 40, 34)
      ..cubicTo(52, 50, 70, 54, 86, 58)
      ..cubicTo(94, 62, 94, 72, 86, 74)
      ..close(), fill: _pink);
    d(Path()
      ..moveTo(10, 72)
      ..lineTo(86, 74)
      ..lineTo(88, 82)
      ..lineTo(10, 82)
      ..close(), fill: _white);
    d(_lines([38, 46, 46, 42, 44, 52, 52, 48]), w: 0.6);
    d(_lines([2, 50, 6, 50, 0, 60, 6, 60]), w: 0.7);
  },
  '🧘‍♀️': (d) {
    d(_circle(50, 20, 11), fill: _orange);
    d(Path()
      ..moveTo(50, 32)
      ..lineTo(50, 62)
      ..moveTo(50, 42)
      ..cubicTo(36, 46, 30, 56, 22, 60)
      ..moveTo(50, 42)
      ..cubicTo(64, 46, 70, 56, 78, 60));
    d(Path()
      ..moveTo(12, 78)
      ..cubicTo(26, 60, 74, 60, 88, 78)
      ..cubicTo(66, 88, 34, 88, 12, 78)
      ..close(), fill: _lilac);
  },
  '🥺': (d) => _face(d, _yellow, () {
        d(_circle(36, 48, 9), fill: _white, w: 0.7);
        d(_circle(64, 48, 9), fill: _white, w: 0.7);
        d.dots([const Offset(36, 50), const Offset(64, 50)], 4);
        d(Path()
          ..moveTo(42, 72)
          ..cubicTo(46, 66, 54, 66, 58, 72), w: 0.8);
      }),

  // ------------------------------------------------------ Caritas (ánimo)
  '😄': (d) => _face(d, _yellow, () {
        d(Path()
          ..moveTo(28, 42)
          ..cubicTo(32, 34, 40, 34, 42, 42)
          ..moveTo(58, 42)
          ..cubicTo(62, 34, 70, 34, 72, 42), w: 0.8);
        d(Path()
          ..moveTo(28, 56)
          ..lineTo(72, 56)
          ..cubicTo(70, 80, 30, 80, 28, 56)
          ..close(), fill: _red, w: 0.8);
      }),
  '😊': (d) => _face(d, _yellow, () {
        d(Path()
          ..moveTo(28, 46)
          ..cubicTo(32, 38, 40, 38, 42, 46)
          ..moveTo(58, 46)
          ..cubicTo(62, 38, 70, 38, 72, 46)
          ..moveTo(34, 62)
          ..cubicTo(42, 74, 58, 74, 66, 62), w: 0.8);
        d(_oval(18, 54, 30, 62), fill: _pink, line: false);
        d(_oval(70, 54, 82, 62), fill: _pink, line: false);
      }),
  '🙂': (d) => _face(d, _green, () {
        d.dots([const Offset(36, 44), const Offset(64, 44)], 4.5);
        d(Path()
          ..moveTo(34, 62)
          ..cubicTo(42, 72, 58, 72, 66, 62), w: 0.8);
      }),
  '😐': (d) => _face(d, _gray, () {
        d.dots([const Offset(36, 44), const Offset(64, 44)], 4.5);
        d(_lines([36, 66, 64, 66]), w: 0.8);
      }),
  '😢': (d) => _face(d, _blue, () {
        d.dots([const Offset(36, 44), const Offset(64, 44)], 4.5);
        d(Path()
          ..moveTo(36, 72)
          ..cubicTo(42, 62, 58, 62, 64, 72), w: 0.8);
        d(Path()
          ..moveTo(30, 52)
          ..cubicTo(34, 58, 34, 64, 30, 64)
          ..cubicTo(26, 64, 26, 58, 30, 52)
          ..close(), fill: _white, w: 0.6);
      }),
  '😭': (d) => _face(d, _blue, () {
        d(_lines([28, 44, 42, 44, 58, 44, 72, 44]), w: 0.8);
        d(_lines([34, 48, 34, 78, 66, 48, 66, 78]), w: 1.1);
        d(_oval(42, 62, 58, 76), fill: _red, w: 0.7);
      }),
  '😠': (d) => _face(d, _red, () {
        d(_lines([26, 34, 42, 40, 74, 34, 58, 40]), w: 0.9);
        d.dots([const Offset(36, 48), const Offset(64, 48)], 4.5);
        d(Path()
          ..moveTo(36, 72)
          ..cubicTo(42, 64, 58, 64, 64, 72), w: 0.8);
      }),
  '😡': (d) => _doodles['😠']!(d),
  '😴': (d) {
    _face(d, _lilac, () {
      d(Path()
        ..moveTo(26, 50)
        ..cubicTo(30, 56, 38, 56, 42, 50)
        ..moveTo(54, 50)
        ..cubicTo(58, 56, 66, 56, 70, 50), w: 0.8);
      d(_oval(42, 64, 54, 76), w: 0.7);
    });
    d(_poly([72, 8, 88, 8, 72, 24, 88, 24], close: false), w: 0.8);
  },
  '😀': (d) => _doodles['😄']!(d),
  '🥰': (d) {
    _doodles['😊']!(d);
    d(_heart(66, 0, 0.3), fill: _pink, w: 0.6);
  },
  '😎': (d) => _face(d, _yellow, () {
        d(Path()
          ..moveTo(16, 40)
          ..lineTo(84, 40)
          ..moveTo(20, 40)
          ..cubicTo(20, 58, 44, 58, 46, 40)
          ..moveTo(54, 40)
          ..cubicTo(56, 58, 80, 58, 80, 40), fill: _inkLight, w: 0.8);
        d(Path()
          ..moveTo(36, 68)
          ..cubicTo(44, 76, 56, 76, 64, 68), w: 0.8);
      }),
  '🤔': (d) => _face(d, _yellow, () {
        d.dots([const Offset(36, 44), const Offset(64, 44)], 4.5);
        d(_lines([26, 32, 42, 30]), w: 0.8);
        d(_lines([40, 68, 62, 64]), w: 0.8);
      }),

  // ------------------------------------------------------------- Marcas
  '✅': (d) {
    d(_rrect(10, 10, 90, 90, 10), fill: _green);
    d(_poly([26, 52, 44, 68, 76, 30], close: false), w: 1.3);
  },
  '❌': (d) => d(_lines([20, 20, 80, 80, 80, 20, 20, 80]), w: 1.6),
  '📌': (d) {
    d(_circle(50, 30, 22), fill: _red);
    d(_lines([50, 52, 50, 94]));
  },
  '📅': (d) {
    d(_rrect(10, 18, 90, 90, 8), fill: _white);
    d(Path()
      ..moveTo(10, 40)
      ..lineTo(10, 26)
      ..cubicTo(10, 20, 14, 18, 18, 18)
      ..lineTo(82, 18)
      ..cubicTo(86, 18, 90, 20, 90, 26)
      ..lineTo(90, 40)
      ..close(), fill: _red);
    d(_lines([30, 8, 30, 26, 70, 8, 70, 26]));
    d.dots([
      for (final x in [30.0, 50.0, 70.0])
        for (final y in [56.0, 74.0]) Offset(x, y),
    ], 3.5);
  },
  '🃏': (d) {
    final m = (Matrix4.identity()
          ..translateByDouble(40, 52, 0, 1)
          ..rotateZ(-0.25))
        .storage;
    d(_rrect(-24, -34, 24, 34, 6).transform(m), fill: _blue);
    d(_rrect(36, 16, 84, 86, 6), fill: _white);
    d(_heart(42, 30, 0.42), fill: _pink, w: 0.7);
  },
  '🔖': (d) => d(_poly([24, 8, 76, 8, 76, 92, 50, 72, 24, 92]), fill: _pink),
};
