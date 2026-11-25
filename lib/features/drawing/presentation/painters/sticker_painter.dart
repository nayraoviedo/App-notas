import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Stickers de gatitos dibujados (imágenes en assets/stickers/).
final catStickerAssets = [
  for (var i = 1; i <= 27; i++) 'assets/stickers/cat_${i.toString().padLeft(2, '0')}.png',
];

/// Pestañas del panel de stickers.
enum StickerCategory {
  cats('Gatitos'),
  mine('Míos'),
  basic('Básico'),
  memo('Memo'),
  text('Texto'),
  natural('Natural'),
  emoji('Emoji');

  const StickerCategory(this.label);
  final String label;
}

/// Un sticker dibujado con código (no son imágenes, así que se ven nítidos
/// a cualquier tamaño y no pesan nada).
class StickerDef {
  const StickerDef(this.id, this.category, this.width, this.height, this.paint);
  final String id;
  final StickerCategory category;
  final double width;
  final double height;
  final void Function(Canvas c, Size s) paint;
}

StickerDef? stickerById(String id) => _byId[id];

List<StickerDef> stickersOf(StickerCategory c) =>
    stickerCatalog.where((s) => s.category == c).toList();

final Map<String, StickerDef> _byId = {for (final s in stickerCatalog) s.id: s};

/// Dibuja el sticker [id] dentro de [size]. Si no existe, no dibuja nada.
void paintSticker(Canvas canvas, String id, Size size) {
  final def = stickerById(id);
  if (def == null) return;
  canvas.save();
  canvas.scale(size.width / def.width, size.height / def.height);
  def.paint(canvas, Size(def.width, def.height));
  canvas.restore();
}

class StickerPainter extends CustomPainter {
  const StickerPainter(this.id);
  final String id;

  @override
  void paint(Canvas canvas, Size size) => paintSticker(canvas, id, size);

  @override
  bool shouldRepaint(StickerPainter old) => old.id != id;
}

// ------------------------------------------------------------------ Colores

const _yellow = Color(0xFFFBE7A1);
const _mint = Color(0xFFCDEBD6);
const _pink = Color(0xFFFBE1E8);
const _blueLine = Color(0xFFEAF3FB);
const _kraft = Color(0xFFC4915E);
const _teal = Color(0xFF3A86A0);
const _cream = Color(0xFFF3EADB);
const _sage = Color(0xFFC1C8BD);
const _orange = Color(0xFFF5B97D);
const _peach = Color(0xFFF0D5BC);
const _coral = Color(0xFFD9705F);
const _rust = Color(0xFFBE6248);
const _mustard = Color(0xFFDFA03F);
const _red = Color(0xFFB04B50);
const _navy = Color(0xFF4F7189);
const _sageDark = Color(0xFF97B3A5);
const _mauve = Color(0xFFDDC9CC);

// ------------------------------------------------------------------ Formas

void _shadow(Canvas c, Path p, {double elevation = 3}) =>
    c.drawShadow(p, Colors.black.withValues(alpha: 0.5), elevation, false);

void _fill(Canvas c, Path p, Color color, {bool shadow = true}) {
  if (shadow) _shadow(c, p);
  c.drawPath(p, Paint()..color = color);
}

Paint _stroke(Color color, double w) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Path _heart(Rect r) {
  final w = r.width, h = r.height;
  final p = Path()..moveTo(r.left + w / 2, r.top + h * 0.95);
  p.cubicTo(r.left - w * 0.05, r.top + h * 0.6, r.left + w * 0.02, r.top - h * 0.02,
      r.left + w * 0.5, r.top + h * 0.25);
  p.cubicTo(r.left + w * 0.98, r.top - h * 0.02, r.left + w * 1.05, r.top + h * 0.6,
      r.left + w / 2, r.top + h * 0.95);
  return p..close();
}

Path _star(Offset c, double outer, double inner, {int points = 5, double rot = -math.pi / 2}) {
  final p = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    final a = rot + i * math.pi / points;
    final pt = c + Offset(math.cos(a) * r, math.sin(a) * r);
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  return p..close();
}

/// Estrella de 4 puntas con lados curvos (brillito).
Path sparklePath(Offset c, double rx, [double? ry]) {
  final r2 = ry ?? rx;
  const k = 0.12;
  final p = Path()..moveTo(c.dx, c.dy - r2);
  p.quadraticBezierTo(c.dx + rx * k, c.dy - r2 * k, c.dx + rx, c.dy);
  p.quadraticBezierTo(c.dx + rx * k, c.dy + r2 * k, c.dx, c.dy + r2);
  p.quadraticBezierTo(c.dx - rx * k, c.dy + r2 * k, c.dx - rx, c.dy);
  p.quadraticBezierTo(c.dx - rx * k, c.dy - r2 * k, c.dx, c.dy - r2);
  return p..close();
}

/// Flor/festón: círculo con "pétalos" redondeados.
Path _scallop(Offset c, double r, int petals, double depth, {double? rx}) {
  final kx = (rx ?? r) / r;
  final p = Path();
  const steps = 180;
  for (var i = 0; i <= steps; i++) {
    final a = i / steps * math.pi * 2;
    final rr = r * (1 - depth + depth * math.cos(a * petals).abs());
    final pt = c + Offset(math.cos(a) * rr * kx, math.sin(a) * rr);
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  return p..close();
}

Path _cloud(Rect r) {
  final p = Path();
  final w = r.width, h = r.height;
  p.addOval(Rect.fromCircle(center: r.topLeft + Offset(w * 0.3, h * 0.55), radius: h * 0.3));
  p.addOval(Rect.fromCircle(center: r.topLeft + Offset(w * 0.5, h * 0.38), radius: h * 0.34));
  p.addOval(Rect.fromCircle(center: r.topLeft + Offset(w * 0.72, h * 0.55), radius: h * 0.3));
  p.addRRect(RRect.fromLTRBR(r.left + w * 0.12, r.top + h * 0.5, r.right - w * 0.1,
      r.top + h * 0.85, Radius.circular(h * 0.18)));
  return p;
}

/// Borde rasgado (zigzag) en los extremos de una cinta.
Path _tape(Rect r, {double tooth = 6}) {
  final p = Path()..moveTo(r.left, r.top);
  p.lineTo(r.right, r.top);
  var y = r.top;
  var out = true;
  while (y < r.bottom) {
    y = math.min(y + tooth, r.bottom);
    p.lineTo(out ? r.right - tooth * 0.6 : r.right, y);
    out = !out;
  }
  p.lineTo(r.left, r.bottom);
  y = r.bottom;
  out = true;
  while (y > r.top) {
    y = math.max(y - tooth, r.top);
    p.lineTo(out ? r.left + tooth * 0.6 : r.left, y);
    out = !out;
  }
  return p..close();
}

void _tapeAt(Canvas c, Offset center, double w, double h, double angle, Color color) {
  c.save();
  c.translate(center.dx, center.dy);
  c.rotate(angle);
  c.drawPath(_tape(Rect.fromCenter(center: Offset.zero, width: w, height: h), tooth: 4),
      Paint()..color = color.withValues(alpha: 0.75));
  c.restore();
}

void _lines(Canvas c, Rect r, int n, Color color, {double width = 1.4}) {
  final p = _stroke(color, width);
  for (var i = 1; i <= n; i++) {
    final y = r.top + r.height * i / (n + 1);
    c.drawLine(Offset(r.left, y), Offset(r.right, y), p);
  }
}

void _clip(Canvas c, Offset at, double h) {
  final p = _stroke(const Color(0xFF8A8F98), h * 0.09);
  final w = h * 0.36;
  final path = Path()
    ..moveTo(at.dx + w * 0.75, at.dy + h * 0.35)
    ..lineTo(at.dx + w * 0.75, at.dy + h * 0.9)
    ..arcToPoint(Offset(at.dx, at.dy + h * 0.9), radius: Radius.circular(w * 0.38))
    ..lineTo(at.dx, at.dy + h * 0.1)
    ..arcToPoint(Offset(at.dx + w, at.dy + h * 0.1), radius: Radius.circular(w * 0.5))
    ..lineTo(at.dx + w, at.dy + h * 0.75);
  c.drawPath(path, p);
}

/// Nota adhesiva con la esquina levantada.
void _stickyNote(Canvas c, Size s, Color color, {bool lined = false, Color? lineColor}) {
  final r = Offset.zero & s;
  final body = Path()
    ..moveTo(r.left, r.top)
    ..lineTo(r.right, r.top)
    ..lineTo(r.right, r.bottom - s.height * 0.12)
    ..quadraticBezierTo(r.right - s.width * 0.02, r.bottom - s.height * 0.02,
        r.right - s.width * 0.14, r.bottom)
    ..lineTo(r.left, r.bottom)
    ..close();
  _fill(c, body, color);
  if (lined) {
    _lines(c, r.deflate(s.width * 0.06), 9, lineColor ?? const Color(0xFFCFE0F2), width: 1.2);
  }
  final curl = Path()
    ..moveTo(r.right, r.bottom - s.height * 0.12)
    ..quadraticBezierTo(r.right - s.width * 0.1, r.bottom - s.height * 0.1,
        r.right - s.width * 0.14, r.bottom)
    ..close();
  c.drawPath(curl, Paint()..color = Color.lerp(color, Colors.black, 0.12)!);
}

/// Círculo con la orilla despegándose.
void _peelCircle(Canvas c, Size s, Color color) {
  final center = s.center(Offset.zero);
  final r = s.shortestSide * 0.46;
  final circle = Path()..addOval(Rect.fromCircle(center: center, radius: r));
  final cutLine = center + Offset(r * 0.42, r * 0.42);
  // Parte pegada (sin la esquina que se levanta).
  final keep = Path.combine(
    PathOperation.difference,
    circle,
    Path()
      ..moveTo(cutLine.dx + r, cutLine.dy - r)
      ..lineTo(cutLine.dx - r, cutLine.dy + r)
      ..lineTo(cutLine.dx + r * 2, cutLine.dy + r * 2)
      ..close(),
  );
  c.drawCircle(center, r + 4, Paint()..color = Colors.white);
  _shadow(c, Path()..addOval(Rect.fromCircle(center: center, radius: r + 4)), elevation: 2);
  c.drawCircle(center, r + 4, Paint()..color = Colors.white);
  c.drawPath(keep, Paint()..color = color);
  // La parte doblada (blanca con sombra).
  final flap = Path()
    ..moveTo(cutLine.dx + r * 0.36, cutLine.dy - r * 0.36)
    ..quadraticBezierTo(cutLine.dx - r * 0.05, cutLine.dy - r * 0.05, cutLine.dx - r * 0.36,
        cutLine.dy + r * 0.36)
    ..quadraticBezierTo(cutLine.dx - r * 0.1, cutLine.dy - r * 0.4, cutLine.dx + r * 0.36,
        cutLine.dy - r * 0.36)
    ..close();
  _shadow(c, flap, elevation: 2);
  c.drawPath(flap, Paint()..color = const Color(0xFFF7F7F7));
}

/// Banderín con punta de flecha.
void _banner(Canvas c, Size s, Color color, {bool notch = false}) {
  final p = Path()..moveTo(0, 0);
  p.lineTo(s.width * 0.88, 0);
  p.lineTo(s.width, s.height / 2);
  p.lineTo(s.width * 0.88, s.height);
  p.lineTo(0, s.height);
  if (notch) p.lineTo(s.width * 0.08, s.height / 2);
  p.close();
  _fill(c, p, color, shadow: false);
}

/// Papel con borde inferior rasgado.
Path _tornPaper(Rect r) {
  final p = Path()..moveTo(r.left, r.top);
  p.lineTo(r.right, r.top);
  p.lineTo(r.right, r.bottom - 8);
  final rnd = math.Random(7);
  for (var x = r.right; x > r.left; x -= 9) {
    p.lineTo(x - 4.5, r.bottom - 8 + rnd.nextDouble() * 10);
  }
  p.lineTo(r.left, r.bottom - 6);
  return p..close();
}

// ------------------------------------------------------------- Catálogo

final stickerCatalog = <StickerDef>[
  // ------------------------------- Básico: cintas, banderines, marcas
  for (final (name, color) in [
    ('tape_beige', const Color(0xFFE9D7B5)),
    ('tape_pink', const Color(0xFFF6C6D2)),
    ('tape_mint', const Color(0xFFB9E2CF)),
    ('tape_blue', const Color(0xFFB8D3F0)),
    ('tape_lilac', const Color(0xFFD9C8F2)),
  ])
    StickerDef(name, StickerCategory.basic, 260, 56, (c, s) {
      c.drawPath(_tape(Offset.zero & s), Paint()..color = color.withValues(alpha: 0.8));
      // Rayitas de washi.
      final p = _stroke(Colors.white.withValues(alpha: 0.35), 5);
      for (var x = 20.0; x < s.width - 10; x += 26) {
        c.drawLine(Offset(x, 4), Offset(x - 12, s.height - 4), p);
      }
    }),
  for (final (name, color, notch) in [
    ('banner_sage', _sage, false),
    ('banner_orange', _orange, false),
    ('banner_peach', _peach, true),
    ('banner_coral', _coral, true),
  ])
    StickerDef(name, StickerCategory.basic, 240, 62, (c, s) => _banner(c, s, color, notch: notch)),
  StickerDef('square_kraft', StickerCategory.basic, 200, 200, (c, s) {
    _fill(c, Path()..addRect(Offset.zero & s), _kraft);
  }),
  StickerDef('square_teal', StickerCategory.basic, 200, 200, (c, s) {
    _fill(c, Path()..addRect(Offset.zero & s), _teal);
  }),
  StickerDef('check', StickerCategory.basic, 180, 180, (c, s) {
    final ctr = s.center(Offset.zero);
    c.drawCircle(ctr, s.width * 0.42, _stroke(const Color(0xFF7D9A4A), s.width * 0.07));
    final p = Path()
      ..moveTo(s.width * 0.28, s.height * 0.52)
      ..lineTo(s.width * 0.45, s.height * 0.7)
      ..lineTo(s.width * 0.9, s.height * 0.12);
    c.drawPath(p, _stroke(const Color(0xFF7D9A4A), s.width * 0.09));
  }),
  StickerDef('cross', StickerCategory.basic, 180, 180, (c, s) {
    final ctr = s.center(Offset.zero);
    final col = const Color(0xFFC0524A);
    c.drawCircle(ctr, s.width * 0.42, _stroke(col, s.width * 0.07));
    c.drawLine(Offset(s.width * 0.3, s.height * 0.3), Offset(s.width * 0.7, s.height * 0.7),
        _stroke(col, s.width * 0.09));
    c.drawLine(Offset(s.width * 0.7, s.height * 0.3), Offset(s.width * 0.3, s.height * 0.7),
        _stroke(col, s.width * 0.09));
  }),
  for (final (name, color) in [
    ('peel_rust', _rust),
    ('peel_mustard', _mustard),
    ('peel_red', _red),
    ('peel_navy', _navy),
  ])
    StickerDef(name, StickerCategory.basic, 180, 180, (c, s) => _peelCircle(c, s, color)),
  StickerDef('note_cream_tape', StickerCategory.basic, 220, 220, (c, s) {
    final r = Rect.fromLTWH(10, 14, s.width - 20, s.height - 20);
    _fill(c, Path()..addRect(r), _cream);
    _lines(c, r.deflate(14), 4, const Color(0xFFCBA36F), width: 3);
    _tapeAt(c, Offset(s.width * 0.82, 18), 30, 60, 0.3, const Color(0xFFC9A26A));
  }),
  StickerDef('note_blush_torn', StickerCategory.basic, 220, 220, (c, s) {
    final r = Rect.fromLTWH(8, 12, s.width - 16, s.height - 18);
    _fill(c, _tornPaper(r), const Color(0xFFF1D7CA));
    c.drawRect(Rect.fromLTWH(r.left, r.top, r.width, 16), Paint()..color = const Color(0xFFAF9A90));
  }),
  StickerDef('note_binder', StickerCategory.basic, 200, 220, (c, s) {
    final r = Rect.fromLTWH(10, 8, s.width - 20, s.height - 16);
    _fill(c, Path()..addRect(r), Colors.white);
    c.drawRect(Rect.fromLTWH(r.left, r.top, 18, r.height), Paint()..color = const Color(0xFFC9B9C8));
    for (final y in [0.25, 0.75]) {
      c.drawCircle(Offset(r.left + 9, r.top + r.height * y), 4, Paint()..color = Colors.white);
    }
  }),

  // --------------------------------------------- Memo: notas adhesivas
  StickerDef('memo_yellow', StickerCategory.memo, 220, 220, (c, s) => _stickyNote(c, s, _yellow)),
  StickerDef('memo_lined', StickerCategory.memo, 220, 220,
      (c, s) => _stickyNote(c, s, _blueLine, lined: true)),
  StickerDef('memo_mint', StickerCategory.memo, 220, 220, (c, s) => _stickyNote(c, s, _mint)),
  StickerDef('memo_pink', StickerCategory.memo, 220, 220, (c, s) => _stickyNote(c, s, _pink)),
  StickerDef('memo_orange', StickerCategory.memo, 220, 220,
      (c, s) => _stickyNote(c, s, const Color(0xFFF4B67D))),
  StickerDef('memo_sage', StickerCategory.memo, 220, 220, (c, s) => _stickyNote(c, s, _sageDark)),
  StickerDef('memo_mauve', StickerCategory.memo, 220, 220, (c, s) => _stickyNote(c, s, _mauve)),
  StickerDef('memo_heart', StickerCategory.memo, 220, 200, (c, s) {
    _fill(c, _heart(Rect.fromLTWH(8, 10, s.width - 16, s.height - 14)), const Color(0xFFF2B8BC));
  }),
  StickerDef('memo_flower', StickerCategory.memo, 220, 220, (c, s) {
    _fill(c, _scallop(s.center(Offset.zero), s.width * 0.46, 4, 0.22), const Color(0xFFFBE3AE));
  }),
  StickerDef('memo_dots', StickerCategory.memo, 220, 220, (c, s) {
    _peelCircle(c, s, const Color(0xFFE6E8EC));
    final rnd = math.Random(3);
    for (var i = 0; i < 14; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = rnd.nextDouble() * s.width * 0.34;
      c.drawCircle(s.center(Offset.zero) + Offset(math.cos(a) * d, math.sin(a) * d), 3.5,
          Paint()..color = const Color(0xFF9DB4D3));
    }
  }),
  StickerDef('memo_cloud', StickerCategory.memo, 240, 200, (c, s) {
    _fill(c, _cloud(Rect.fromLTWH(4, 10, s.width - 8, s.height - 10)), const Color(0xFFE5E0DA));
    _clip(c, Offset(s.width * 0.78, 0), 60);
  }),
  StickerDef('memo_torn_clip', StickerCategory.memo, 220, 230, (c, s) {
    final r = Rect.fromLTWH(8, 18, s.width - 16, s.height - 22);
    _fill(c, _tornPaper(r), const Color(0xFFF1F1F1));
    final dots = Paint()..color = const Color(0xFFD5D5D5);
    for (var x = r.left + 10; x < r.right - 10; x += 12) {
      c.drawCircle(Offset(x, r.top + 8), 2.5, dots);
    }
    _clip(c, Offset(s.width * 0.7, 0), 56);
  }),
  StickerDef('memo_pink_taped', StickerCategory.memo, 220, 220, (c, s) {
    c.save();
    c.translate(s.width / 2, s.height / 2);
    c.rotate(0.05);
    _fill(c, _tornPaper(Rect.fromCenter(center: Offset.zero, width: s.width * 0.78, height: s.height * 0.74)),
        const Color(0xFFF2C6DA));
    c.restore();
    _tapeAt(c, Offset(s.width * 0.2, s.height * 0.18), 70, 22, -0.5, const Color(0xFFC6B5F0));
    _tapeAt(c, Offset(s.width * 0.78, s.height * 0.18), 70, 22, 0.5, const Color(0xFFC6B5F0));
  }),
  StickerDef('memo_gray_lined', StickerCategory.memo, 220, 220, (c, s) {
    final r = RRect.fromLTRBR(14, 22, s.width - 14, s.height - 6, const Radius.circular(14));
    _fill(c, Path()..addRRect(r), const Color(0xFFD9E2E3));
    _lines(c, r.outerRect.deflate(14), 6, Colors.white, width: 2);
    _tapeAt(c, Offset(s.width / 2, 22), 80, 20, 0, const Color(0xFF8DB9A2));
  }),
  StickerDef('memo_blue_taped', StickerCategory.memo, 220, 220, (c, s) {
    c.save();
    c.translate(s.width / 2, s.height / 2);
    c.rotate(-0.04);
    _fill(c, _tornPaper(Rect.fromCenter(center: Offset.zero, width: s.width * 0.8, height: s.height * 0.72)),
        const Color(0xFFB2CDF2));
    c.restore();
    _tapeAt(c, Offset(s.width * 0.18, s.height * 0.2), 70, 22, -0.5, const Color(0xFFF08B8B));
    _tapeAt(c, Offset(s.width * 0.8, s.height * 0.2), 70, 22, 0.45, const Color(0xFFF08B8B));
  }),
  StickerDef('memo_label_blue', StickerCategory.memo, 240, 150, (c, s) {
    final r = RRect.fromLTRBR(4, 22, s.width - 4, s.height - 4, const Radius.circular(30));
    _fill(c, Path()..addRRect(r), const Color(0xFF7FA8D8));
    for (final x in [0.2, 0.8]) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s.width * x, 22), width: 18, height: 38),
          const Radius.circular(4)), Paint()..color = const Color(0xFF3E4A6B));
    }
  }),
  StickerDef('memo_purple_block', StickerCategory.memo, 220, 200, (c, s) {
    final p = Path()
      ..moveTo(8, 14)
      ..lineTo(s.width - 8, 8)
      ..lineTo(s.width - 4, s.height - 10)
      ..lineTo(6, s.height - 4)
      ..close();
    _fill(c, p, const Color(0xFF8580BC));
    _lines(c, Rect.fromLTRB(26, 30, s.width - 26, s.height - 22), 3, Colors.white.withValues(alpha: 0.7),
        width: 2);
  }),

  // --------------------------------------------------- Natural
  StickerDef('sparkle', StickerCategory.natural, 160, 200, (c, s) {
    c.drawPath(sparklePath(s.center(Offset.zero), s.width * 0.42, s.height * 0.46),
        Paint()..color = const Color(0xFFF7C21E));
  }),
  StickerDef('heart', StickerCategory.natural, 200, 180, (c, s) {
    c.drawPath(_heart(Offset.zero & s), Paint()..color = const Color(0xFFF6A6BD));
  }),
  StickerDef('star', StickerCategory.natural, 200, 200, (c, s) {
    final p = _star(s.center(Offset.zero), s.width * 0.48, s.width * 0.22);
    c.drawPath(p, Paint()..color = const Color(0xFF6E9FD9));
    c.drawPath(p, _stroke(const Color(0xFF6E9FD9), 10));
  }),
  StickerDef('sun', StickerCategory.natural, 200, 200, (c, s) {
    final ctr = s.center(Offset.zero);
    c.drawCircle(ctr, s.width * 0.2, Paint()..color = const Color(0xFFF28C28));
    final p = _stroke(const Color(0xFFF28C28), 9);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + 0.2;
      c.drawLine(ctr + Offset(math.cos(a), math.sin(a)) * s.width * 0.3,
          ctr + Offset(math.cos(a), math.sin(a)) * s.width * 0.43, p);
    }
  }),
  StickerDef('lightning', StickerCategory.natural, 140, 220, (c, s) {
    final p = Path()
      ..moveTo(s.width * 0.62, 0)
      ..lineTo(s.width * 0.08, s.height * 0.55)
      ..lineTo(s.width * 0.48, s.height * 0.55)
      ..lineTo(s.width * 0.3, s.height)
      ..lineTo(s.width * 0.95, s.height * 0.4)
      ..lineTo(s.width * 0.55, s.height * 0.4)
      ..close();
    c.drawPath(p, Paint()..color = const Color(0xFFF3D800));
  }),
  StickerDef('cloud_outline', StickerCategory.natural, 240, 170, (c, s) {
    c.drawPath(_scallop(s.center(Offset.zero), s.height * 0.42, 5, 0.18, rx: s.width * 0.44),
        _stroke(const Color(0xFF7DD6EA), 9));
  }),
  StickerDef('flower', StickerCategory.natural, 200, 200, (c, s) {
    final ctr = s.center(Offset.zero);
    c.drawPath(_scallop(ctr, s.width * 0.47, 3, 0.45), Paint()..color = const Color(0xFFF8CA25));
    c.drawOval(Rect.fromCenter(center: ctr, width: s.width * 0.22, height: s.width * 0.18),
        Paint()..color = const Color(0xFF8E44AD));
  }),
  StickerDef('rainbow_lines', StickerCategory.natural, 220, 130, (c, s) {
    const colors = [
      Color(0xFFE57373), Color(0xFFFFB74D), Color(0xFFFFF176), Color(0xFF81C784), Color(0xFF64B5F6),
      Color(0xFF9575CD),
    ];
    for (var i = 0; i < colors.length; i++) {
      final r = s.width * 0.46 - i * 9;
      c.drawArc(Rect.fromCircle(center: Offset(s.width / 2, s.height), radius: r), math.pi, math.pi,
          false, _stroke(colors[i], 4));
    }
  }),
  StickerDef('rainbow_bold', StickerCategory.natural, 220, 130, (c, s) {
    const colors = [Color(0xFFE53935), Color(0xFF1E5BB8), Color(0xFF26A69A)];
    for (var i = 0; i < colors.length; i++) {
      final r = s.width * 0.42 - i * 22;
      c.drawArc(Rect.fromCircle(center: Offset(s.width / 2, s.height), radius: r), math.pi, math.pi,
          false, _stroke(colors[i], 20)..strokeCap = StrokeCap.butt);
    }
    final dots = Paint()..color = const Color(0xFFF2C14E);
    for (var a = math.pi; a <= math.pi * 2; a += math.pi / 14) {
      c.drawCircle(Offset(s.width / 2, s.height) + Offset(math.cos(a), math.sin(a)) * (s.width * 0.5), 3, dots);
    }
  }),
  StickerDef('tulip', StickerCategory.natural, 140, 220, (c, s) {
    final stem = Path()
      ..moveTo(s.width * 0.5, s.height * 0.4)
      ..quadraticBezierTo(s.width * 0.45, s.height * 0.75, s.width * 0.3, s.height);
    c.drawPath(stem, _stroke(const Color(0xFF9DB84A), 9));
    final leaf = Path()
      ..moveTo(s.width * 0.4, s.height * 0.85)
      ..quadraticBezierTo(s.width * 0.7, s.height * 0.6, s.width * 0.95, s.height * 0.65)
      ..quadraticBezierTo(s.width * 0.75, s.height * 0.85, s.width * 0.4, s.height * 0.85);
    c.drawPath(leaf, Paint()..color = const Color(0xFF9DB84A));
    final head = Path()
      ..moveTo(s.width * 0.25, s.height * 0.08)
      ..lineTo(s.width * 0.4, s.height * 0.2)
      ..lineTo(s.width * 0.55, 0)
      ..lineTo(s.width * 0.68, s.height * 0.2)
      ..lineTo(s.width * 0.85, s.height * 0.08)
      ..quadraticBezierTo(s.width * 0.9, s.height * 0.42, s.width * 0.52, s.height * 0.42)
      ..quadraticBezierTo(s.width * 0.18, s.height * 0.4, s.width * 0.25, s.height * 0.08)
      ..close();
    c.drawPath(head, Paint()..color = const Color(0xFFF26B4F));
  }),
  StickerDef('pine', StickerCategory.natural, 150, 220, (c, s) {
    c.drawRect(Rect.fromLTWH(s.width * 0.45, s.height * 0.8, s.width * 0.1, s.height * 0.2),
        Paint()..color = const Color(0xFF8D6E63));
    final green = Paint()..color = const Color(0xFF7CB342);
    for (var i = 0; i < 3; i++) {
      final top = s.height * (0.08 + i * 0.22);
      final w = s.width * (0.5 + i * 0.22);
      c.drawPath(
          Path()
            ..moveTo(s.width / 2, top)
            ..lineTo(s.width / 2 + w / 2, top + s.height * 0.32)
            ..lineTo(s.width / 2 - w / 2, top + s.height * 0.32)
            ..close(),
          green);
    }
    c.drawPath(_star(Offset(s.width / 2, s.height * 0.07), 14, 6), Paint()..color = const Color(0xFFFFB74D));
  }),
  StickerDef('vase', StickerCategory.natural, 140, 220, (c, s) {
    final ink = _stroke(const Color(0xFF2B2B2B), 4);
    final vase = Path()
      ..moveTo(s.width * 0.3, s.height * 0.5)
      ..lineTo(s.width * 0.7, s.height * 0.5)
      ..lineTo(s.width * 0.7, s.height * 0.6)
      ..quadraticBezierTo(s.width * 0.85, s.height * 0.65, s.width * 0.82, s.height * 0.95)
      ..lineTo(s.width * 0.18, s.height * 0.95)
      ..quadraticBezierTo(s.width * 0.15, s.height * 0.65, s.width * 0.3, s.height * 0.6)
      ..close();
    c.drawPath(vase, Paint()..color = Colors.white);
    c.drawPath(vase, ink);
    final stems = _stroke(const Color(0xFF9DB84A), 4);
    for (final (x, top) in [(0.4, 0.15), (0.6, 0.08)]) {
      c.drawLine(Offset(s.width * x, s.height * 0.9), Offset(s.width * x, s.height * top), stems);
      c.drawPath(_scallop(Offset(s.width * x, s.height * top), 14, 3, 0.4),
          Paint()..color = const Color(0xFFF26B4F));
    }
  }),
  StickerDef('plant', StickerCategory.natural, 160, 220, (c, s) {
    final pot = Path()
      ..moveTo(s.width * 0.18, s.height * 0.55)
      ..lineTo(s.width * 0.82, s.height * 0.55)
      ..lineTo(s.width * 0.72, s.height * 0.98)
      ..lineTo(s.width * 0.28, s.height * 0.98)
      ..close();
    c.drawPath(pot, Paint()..color = const Color(0xFF9CC28E));
    c.drawPath(pot, _stroke(const Color(0xFF4E5D45), 3));
    final leaf = Paint()..color = Colors.white;
    final ink = _stroke(const Color(0xFF4E5D45), 3);
    for (final (dx, h, lean) in [(0.3, 0.42, -0.15), (0.45, 0.5, -0.05), (0.55, 0.52, 0.05), (0.7, 0.4, 0.15)]) {
      final base = Offset(s.width * dx, s.height * 0.56);
      final tip = Offset(s.width * (dx + lean), s.height * (0.56 - h));
      final p = Path()
        ..moveTo(base.dx - 8, base.dy)
        ..quadraticBezierTo(base.dx - 10, (base.dy + tip.dy) / 2, tip.dx, tip.dy)
        ..quadraticBezierTo(base.dx + 10, (base.dy + tip.dy) / 2, base.dx + 8, base.dy)
        ..close();
      c.drawPath(p, leaf);
      c.drawPath(p, ink);
    }
  }),
  StickerDef('cactus', StickerCategory.natural, 180, 220, (c, s) {
    final green = Paint()..color = const Color(0xFF1FB58F);
    final ink = _stroke(const Color(0xFF1D3B33), 4);
    final body = RRect.fromLTRBR(s.width * 0.36, s.height * 0.12, s.width * 0.64, s.height * 0.82,
        Radius.circular(s.width * 0.14));
    final armL = RRect.fromLTRBR(s.width * 0.12, s.height * 0.3, s.width * 0.3, s.height * 0.6,
        Radius.circular(s.width * 0.09));
    final armR = RRect.fromLTRBR(s.width * 0.7, s.height * 0.22, s.width * 0.88, s.height * 0.52,
        Radius.circular(s.width * 0.09));
    for (final r in [body, armL, armR]) {
      c.drawRRect(r, green);
      c.drawRRect(r, ink);
    }
    c.drawRect(Rect.fromLTRB(s.width * 0.28, s.height * 0.58, s.width * 0.36, s.height * 0.62), green);
    c.drawRect(Rect.fromLTRB(s.width * 0.64, s.height * 0.48, s.width * 0.72, s.height * 0.52), green);
    final pot = Rect.fromLTRB(s.width * 0.22, s.height * 0.8, s.width * 0.78, s.height * 0.98);
    c.drawRect(pot, Paint()..color = const Color(0xFFF2C230));
    c.drawRect(pot, ink);
  }),
  StickerDef('leaf', StickerCategory.natural, 200, 160, (c, s) {
    final p = Path()
      ..moveTo(10, s.height * 0.8)
      ..quadraticBezierTo(s.width * 0.3, 0, s.width - 10, s.height * 0.2)
      ..quadraticBezierTo(s.width * 0.7, s.height, 10, s.height * 0.8)
      ..close();
    c.drawPath(p, Paint()..color = const Color(0xFF8BC34A));
    c.drawLine(Offset(10, s.height * 0.8), Offset(s.width * 0.75, s.height * 0.35),
        _stroke(const Color(0xFF558B2F), 4));
  }),
  StickerDef('moon', StickerCategory.natural, 180, 200, (c, s) {
    final full = Path()..addOval(Rect.fromCircle(center: s.center(Offset.zero), radius: s.width * 0.42));
    final bite = Path()
      ..addOval(Rect.fromCircle(center: s.center(Offset(s.width * 0.22, -s.height * 0.1)),
          radius: s.width * 0.36));
    c.drawPath(Path.combine(PathOperation.difference, full, bite), Paint()..color = const Color(0xFFFFD54F));
  }),
  StickerDef('mushroom', StickerCategory.natural, 180, 200, (c, s) {
    c.drawRRect(RRect.fromLTRBR(s.width * 0.38, s.height * 0.45, s.width * 0.62, s.height * 0.95,
        const Radius.circular(16)), Paint()..color = const Color(0xFFF3E5C9));
    final cap = Path()
      ..moveTo(s.width * 0.05, s.height * 0.5)
      ..quadraticBezierTo(s.width * 0.5, -s.height * 0.25, s.width * 0.95, s.height * 0.5)
      ..close();
    c.drawPath(cap, Paint()..color = const Color(0xFFE55B4D));
    final dot = Paint()..color = Colors.white;
    for (final o in [const Offset(0.3, 0.32), const Offset(0.55, 0.2), const Offset(0.72, 0.38)]) {
      c.drawCircle(Offset(s.width * o.dx, s.height * o.dy), s.width * 0.055, dot);
    }
  }),
];

// ------------------------------------------------------ Stickers de texto

/// Stickers de texto (se insertan como texto editable con estilo).
class TextSticker {
  const TextSticker(this.text, this.font, this.color, {this.group = 'Día', this.background});
  final String text;
  final String font;
  final int color;
  final String group;
  final int? background;
}

const _scriptFonts = ['Pacifico', 'Dancing Script', 'Great Vibes', 'Satisfy', 'Allura', 'Sacramento'];
const _textColors = [
  0xFFE2C044, 0xFF7CA65A, 0xFFE38B3C, 0xFF4E8C7A, 0xFFB5423E, 0xFF5E9CA8, 0xFF6E3B8F,
];

/// Stickers con la fecha de hoy (se calculan al abrir el panel).
List<TextSticker> dateStickers([DateTime? now]) {
  final d = now ?? DateTime.now();
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  const mesesL = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
      'septiembre', 'octubre', 'noviembre', 'diciembre'];
  const dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  final dd = d.day.toString().padLeft(2, '0'), mm = d.month.toString().padLeft(2, '0');
  return [
    TextSticker('Hoy · ${d.day} ${meses[d.month - 1]}', 'Pacifico', 0xFFFFFFFF,
        group: 'Fecha', background: 0xFFE07B55),
    TextSticker('${dias[d.weekday - 1]} ${d.day}', 'Dancing Script', 0xFF4E8C7A, group: 'Fecha'),
    TextSticker('${d.day} de ${mesesL[d.month - 1]}', 'Satisfy', 0xFF6E3B8F, group: 'Fecha'),
    TextSticker('$dd/$mm/${d.year}', 'Caveat', 0xFF3B2A22, group: 'Fecha', background: 0xFFFFF1B8),
    TextSticker('$dd.$mm', 'Pacifico', 0xFFB5423E, group: 'Fecha'),
    TextSticker('${mesesL[d.month - 1][0].toUpperCase()}${mesesL[d.month - 1].substring(1)} ${d.year}',
        'Great Vibes', 0xFF5E9CA8, group: 'Fecha'),
  ];
}

final textStickers = <TextSticker>[
  for (final (i, d) in ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'].indexed)
    TextSticker(d, i.isEven ? 'Pacifico' : 'Dancing Script', _textColors[i % _textColors.length]),
  for (final (i, d) in ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'].indexed)
    TextSticker(d, 'Satisfy', 0xFFFFFFFF,
        background: const [0xFFF0C27F, 0xFF9CC5E8, 0xFFB7D99A, 0xFFF2A7B8, 0xFFC9B3E8, 0xFFF6D365, 0xFF9AD3C6][i]),
  for (final (i, m) in [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ].indexed)
    TextSticker(m, _scriptFonts[i % _scriptFonts.length], _textColors[(i + 2) % _textColors.length],
        group: 'Mes'),
  for (final (i, h) in ['Notas', 'Pendientes', 'Ideas', 'Metas', 'Importante', 'Recordar', '¡Hecho!', 'Gracias']
      .indexed)
    TextSticker(h, i.isEven ? 'Great Vibes' : 'Pacifico', _textColors[(i + 4) % _textColors.length],
        group: 'Título'),
];

// ------------------------------------------------------------- Emojis

const emojiStickers = [
  '😀', '😊', '🥰', '😍', '😎', '🤓', '🥳', '😴', '🤔', '😭', '😡', '🤯',
  '👍', '👏', '🙌', '💪', '✌️', '🙏', '❤️', '🧡', '💛', '💚', '💙', '💜',
  '⭐', '✨', '🌟', '🔥', '💡', '📌', '📎', '✏️', '📚', '📝', '📅', '⏰',
  '✅', '❌', '⚠️', '❓', '❗', '💯', '🎯', '🏆', '🎉', '🎁', '☕', '🍰',
  '🌸', '🌷', '🌻', '🍀', '🌈', '☀️', '🌙', '☁️', '🐱', '🐶', '🐰', '🦋',
];
