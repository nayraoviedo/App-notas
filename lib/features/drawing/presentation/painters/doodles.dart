import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sticker_painter.dart';

/// Doodles: dibujitos hechos "a mano" (trazo café un poco tembloroso y
/// relleno pastel corrido, como impresión riso). Se diseñan en un cuadro de
/// 100×100 y se escalan.
const _ink = Color(0xFF3B2A22);
const _pink = Color(0xFFF7B6C8);
const _yellow = Color(0xFFFFE08A);
const _blue = Color(0xFFB8D8F2);
const _green = Color(0xFFBFE3B4);
const _orange = Color(0xFFF9C99A);
const _lilac = Color(0xFFD9C6F2);

/// Pinta un doodle: relleno (corrido) + trazo doble a mano.
void _doodle(Canvas c, Size s, Path Function() build, {Color? fill, double stroke = 3.4, bool fillOnly = false}) {
  final k = math.min(s.width, s.height) / 100;
  c.save();
  c.translate((s.width - 100 * k) / 2, (s.height - 100 * k) / 2);
  c.scale(k);
  final p = build();
  if (fill != null) {
    c.save();
    c.translate(2.2, 2.4); // relleno un poco corrido
    c.drawPath(p, Paint()..color = fill);
    c.restore();
  }
  if (!fillOnly) {
    final ink = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    c.drawPath(p, ink);
    // Segunda pasada, apenas movida: parece lápiz.
    c.save();
    c.translate(0.7, -0.5);
    c.drawPath(p, ink..color = _ink.withValues(alpha: 0.35)..strokeWidth = stroke * 0.55);
    c.restore();
  }
  c.restore();
}

Path _heart() => Path()
  ..moveTo(50, 86)
  ..cubicTo(18, 64, 8, 44, 16, 28)
  ..cubicTo(24, 12, 44, 14, 50, 32)
  ..cubicTo(57, 13, 78, 11, 86, 28)
  ..cubicTo(94, 46, 80, 65, 50, 86)
  ..close();

Path _star(double cx, double cy, double r, {int points = 5, double inner = 0.45, double rot = -math.pi / 2}) {
  final p = Path();
  for (var i = 0; i < points * 2; i++) {
    final rr = i.isEven ? r : r * inner;
    final a = rot + i * math.pi / points;
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

Path _cloud() => Path()
  ..moveTo(22, 70)
  ..cubicTo(8, 70, 8, 50, 22, 50)
  ..cubicTo(20, 34, 40, 28, 48, 38)
  ..cubicTo(54, 22, 80, 24, 80, 44)
  ..cubicTo(96, 44, 96, 70, 80, 70)
  ..close();

final doodleStickers = <StickerDef>[
  StickerDef('doodle_heart', StickerCategory.doodle, 180, 170,
      (c, s) => _doodle(c, s, _heart, fill: _pink)),
  StickerDef('doodle_star', StickerCategory.doodle, 180, 180,
      (c, s) => _doodle(c, s, () => _star(50, 54, 42), fill: _yellow)),
  StickerDef('doodle_sparkles', StickerCategory.doodle, 180, 180, (c, s) {
    _doodle(c, s, () => _sparkle(40, 55, 30), fill: _yellow);
    _doodle(c, s, () => _sparkle(78, 22, 14), fill: _yellow);
    _doodle(c, s, () => _sparkle(80, 80, 9));
  }),
  StickerDef('doodle_cloud', StickerCategory.doodle, 220, 150,
      (c, s) => _doodle(c, s, _cloud, fill: _blue)),
  StickerDef('doodle_sun', StickerCategory.doodle, 190, 190, (c, s) {
    _doodle(c, s, () => Path()..addOval(Rect.fromCircle(center: const Offset(50, 50), radius: 20)), fill: _yellow);
    _doodle(c, s, () {
      final p = Path();
      for (var i = 0; i < 10; i++) {
        final a = i * math.pi / 5;
        p
          ..moveTo(50 + 28 * math.cos(a), 50 + 28 * math.sin(a))
          ..lineTo(50 + (i.isEven ? 42 : 37) * math.cos(a), 50 + (i.isEven ? 42 : 37) * math.sin(a));
      }
      return p;
    });
  }),
  StickerDef('doodle_flower', StickerCategory.doodle, 160, 200, (c, s) {
    _doodle(c, s, () {
      final p = Path();
      for (var i = 0; i < 5; i++) {
        final a = -math.pi / 2 + i * 2 * math.pi / 5;
        p.addOval(Rect.fromCenter(
            center: Offset(50 + 15 * math.cos(a), 32 + 15 * math.sin(a)), width: 20, height: 20));
      }
      return p;
    }, fill: _pink);
    _doodle(c, s, () => Path()..addOval(Rect.fromCircle(center: const Offset(50, 32), radius: 7)), fill: _yellow);
    _doodle(c, s, () => Path()
      ..moveTo(50, 50)
      ..cubicTo(48, 66, 52, 80, 50, 96)
      ..moveTo(50, 78)
      ..cubicTo(60, 70, 70, 70, 74, 66)
      ..cubicTo(66, 76, 58, 78, 50, 78));
  }),
  StickerDef('doodle_arrow', StickerCategory.doodle, 220, 120, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(8, 70)
      ..cubicTo(30, 30, 50, 90, 70, 50)
      ..cubicTo(76, 38, 84, 36, 90, 38)
      ..moveTo(78, 28)
      ..lineTo(91, 38)
      ..lineTo(80, 50));
  }),
  StickerDef('doodle_arrow_loop', StickerCategory.doodle, 200, 160, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(10, 30)
      ..cubicTo(40, 20, 60, 30, 56, 50)
      ..cubicTo(52, 68, 30, 64, 38, 50)
      ..cubicTo(46, 38, 70, 52, 88, 76)
      ..moveTo(76, 76)
      ..lineTo(89, 77)
      ..lineTo(87, 63));
  }),
  StickerDef('doodle_underline', StickerCategory.doodle, 260, 70, (c, s) {
    _doodle(c, s, () {
      final p = Path()..moveTo(4, 52);
      for (var x = 4.0; x < 96; x += 8) {
        p.quadraticBezierTo(x + 2, 44, x + 4, 52);
        p.quadraticBezierTo(x + 6, 60, x + 8, 52);
      }
      return p;
    });
  }),
  StickerDef('doodle_circle', StickerCategory.doodle, 240, 160, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(62, 14)
      ..cubicTo(20, 8, 2, 40, 10, 62)
      ..cubicTo(20, 90, 82, 92, 94, 60)
      ..cubicTo(102, 36, 76, 14, 40, 18), stroke: 3);
  }),
  StickerDef('doodle_bubble', StickerCategory.doodle, 220, 180, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(20, 18)
      ..lineTo(86, 16)
      ..quadraticBezierTo(94, 16, 94, 26)
      ..lineTo(93, 58)
      ..quadraticBezierTo(93, 66, 84, 66)
      ..lineTo(40, 66)
      ..lineTo(24, 84)
      ..lineTo(28, 66)
      ..lineTo(16, 66)
      ..quadraticBezierTo(8, 66, 8, 58)
      ..lineTo(9, 26)
      ..quadraticBezierTo(10, 18, 20, 18)
      ..close(), fill: Colors.white);
  }),
  StickerDef('doodle_bulb', StickerCategory.doodle, 160, 200, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(38, 66)
      ..cubicTo(20, 52, 22, 14, 50, 12)
      ..cubicTo(78, 14, 80, 52, 62, 66)
      ..lineTo(62, 76)
      ..lineTo(38, 76)
      ..close(), fill: _yellow);
    _doodle(c, s, () => Path()
      ..moveTo(40, 82)
      ..lineTo(60, 82)
      ..moveTo(43, 88)
      ..lineTo(57, 88)
      ..moveTo(44, 50)
      ..lineTo(50, 40)
      ..lineTo(56, 50));
    _doodle(c, s, () => Path()
      ..moveTo(8, 22)
      ..lineTo(16, 26)
      ..moveTo(92, 22)
      ..lineTo(84, 26)
      ..moveTo(50, 2)
      ..lineTo(50, 6));
  }),
  StickerDef('doodle_coffee', StickerCategory.doodle, 190, 190, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(20, 40)
      ..lineTo(72, 40)
      ..lineTo(68, 84)
      ..quadraticBezierTo(46, 92, 24, 84)
      ..close(), fill: _orange);
    _doodle(c, s, () => Path()
      ..moveTo(71, 50)
      ..cubicTo(90, 46, 90, 72, 69, 70)
      ..moveTo(36, 30)
      ..cubicTo(30, 22, 42, 18, 36, 8)
      ..moveTo(52, 30)
      ..cubicTo(46, 22, 58, 18, 52, 8));
  }),
  StickerDef('doodle_moon', StickerCategory.doodle, 180, 180, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(56, 12)
      ..cubicTo(20, 16, 14, 74, 52, 86)
      ..cubicTo(70, 92, 86, 82, 90, 70)
      ..cubicTo(56, 76, 36, 44, 56, 12)
      ..close(), fill: _lilac);
    _doodle(c, s, () => _sparkle(78, 26, 9));
    _doodle(c, s, () => _sparkle(88, 50, 5));
  }),
  StickerDef('doodle_music', StickerCategory.doodle, 170, 190, (c, s) {
    _doodle(c, s, () => Path()
      ..addOval(Rect.fromCenter(center: const Offset(30, 78), width: 22, height: 16))
      ..addOval(Rect.fromCenter(center: const Offset(74, 70), width: 22, height: 16)), fill: _ink);
    _doodle(c, s, () => Path()
      ..moveTo(40, 76)
      ..lineTo(40, 18)
      ..lineTo(84, 10)
      ..lineTo(84, 68)
      ..moveTo(40, 30)
      ..lineTo(84, 22));
  }),
  StickerDef('doodle_paw', StickerCategory.doodle, 170, 170, (c, s) {
    _doodle(c, s, () => Path()
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
  }),
  StickerDef('doodle_crown', StickerCategory.doodle, 200, 160, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(14, 74)
      ..lineTo(10, 30)
      ..lineTo(32, 50)
      ..lineTo(50, 20)
      ..lineTo(68, 50)
      ..lineTo(90, 30)
      ..lineTo(86, 74)
      ..close(), fill: _yellow);
    _doodle(c, s, () => Path()
      ..moveTo(16, 84)
      ..lineTo(84, 84)
      ..addOval(Rect.fromCircle(center: const Offset(50, 62), radius: 5)));
  }),
  StickerDef('doodle_leaves', StickerCategory.doodle, 150, 210, (c, s) {
    _doodle(c, s, () {
      final p = Path()
        ..moveTo(50, 96)
        ..cubicTo(46, 70, 54, 40, 50, 6);
      for (final (y, dir) in [(24.0, -1), (38.0, 1), (54.0, -1), (68.0, 1)]) {
        p
          ..moveTo(50, y + 8)
          ..cubicTo(50 + dir * 10, y, 50 + dir * 28, y - 4, 50 + dir * 32, y - 10)
          ..cubicTo(50 + dir * 24, y + 6, 50 + dir * 10, y + 10, 50, y + 8);
      }
      return p;
    }, fill: _green);
  }),
  StickerDef('doodle_check', StickerCategory.doodle, 170, 170, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(14, 16)
      ..lineTo(80, 14)
      ..lineTo(82, 82)
      ..lineTo(16, 84)
      ..close(), fill: _green);
    _doodle(c, s, () => Path()
      ..moveTo(28, 50)
      ..lineTo(44, 66)
      ..lineTo(96, 8), stroke: 5);
  }),
  StickerDef('doodle_burst', StickerCategory.doodle, 190, 190, (c, s) {
    _doodle(c, s, () => _star(50, 50, 46, points: 12, inner: 0.72), fill: _orange);
    _doodle(c, s, () => Path()
      ..moveTo(50, 28)
      ..lineTo(50, 56)
      ..addOval(Rect.fromCircle(center: const Offset(50, 68), radius: 2.5)), stroke: 6);
  }),
  StickerDef('doodle_pencil', StickerCategory.doodle, 220, 110, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(10, 50)
      ..lineTo(26, 40)
      ..lineTo(88, 40)
      ..lineTo(88, 60)
      ..lineTo(26, 60)
      ..close(), fill: _yellow);
    _doodle(c, s, () => Path()
      ..moveTo(26, 40)
      ..lineTo(26, 60)
      ..moveTo(78, 40)
      ..lineTo(78, 60)
      ..moveTo(10, 50)
      ..lineTo(16, 47)
      ..lineTo(16, 53)
      ..close(), fill: _pink);
  }),
  StickerDef('doodle_book', StickerCategory.doodle, 210, 160, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(50, 28)
      ..cubicTo(36, 18, 20, 18, 8, 24)
      ..lineTo(8, 80)
      ..cubicTo(20, 74, 36, 74, 50, 84)
      ..cubicTo(64, 74, 80, 74, 92, 80)
      ..lineTo(92, 24)
      ..cubicTo(80, 18, 64, 18, 50, 28)
      ..close(), fill: _blue);
    _doodle(c, s, () => Path()
      ..moveTo(50, 28)
      ..lineTo(50, 84)
      ..moveTo(18, 38)
      ..lineTo(40, 40)
      ..moveTo(18, 50)
      ..lineTo(40, 52)
      ..moveTo(60, 40)
      ..lineTo(82, 38)
      ..moveTo(60, 52)
      ..lineTo(82, 50), stroke: 2.6);
  }),
  StickerDef('doodle_rainbow', StickerCategory.doodle, 220, 140, (c, s) {
    for (final (i, col) in [_pink, _yellow, _blue].indexed) {
      final r = 40.0 - i * 10;
      _doodle(c, s, () => Path()
        ..moveTo(50 - r, 72)
        ..arcToPoint(Offset(50 + r, 72), radius: Radius.circular(r))
        ..lineTo(50 + r - 8, 72)
        ..arcToPoint(Offset(50 - r + 8, 72), radius: Radius.circular(r - 8), clockwise: false)
        ..close(), fill: col);
    }
    _doodle(c, s, () => Path()
      ..moveTo(4, 78)
      ..cubicTo(4, 66, 22, 66, 22, 78)
      ..close()
      ..moveTo(78, 78)
      ..cubicTo(78, 66, 96, 66, 96, 78)
      ..close(), fill: Colors.white);
  }),
  StickerDef('doodle_cat', StickerCategory.doodle, 190, 170, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(18, 46)
      ..lineTo(16, 12)
      ..lineTo(38, 30)
      ..cubicTo(46, 27, 54, 27, 62, 30)
      ..lineTo(84, 12)
      ..lineTo(82, 46)
      ..cubicTo(90, 76, 70, 88, 50, 88)
      ..cubicTo(30, 88, 10, 76, 18, 46)
      ..close(), fill: _orange);
    _doodle(c, s, () => Path()
      ..addOval(Rect.fromCircle(center: const Offset(36, 56), radius: 3))
      ..addOval(Rect.fromCircle(center: const Offset(64, 56), radius: 3))
      ..moveTo(44, 66)
      ..quadraticBezierTo(50, 72, 50, 64)
      ..quadraticBezierTo(50, 72, 56, 66)
      ..moveTo(6, 60)
      ..lineTo(24, 62)
      ..moveTo(94, 60)
      ..lineTo(76, 62), stroke: 3);
  }),
  StickerDef('doodle_bow', StickerCategory.doodle, 200, 140, (c, s) {
    _doodle(c, s, () => Path()
      ..moveTo(50, 46)
      ..cubicTo(30, 20, 8, 24, 10, 46)
      ..cubicTo(12, 66, 32, 66, 50, 50)
      ..cubicTo(68, 66, 88, 66, 90, 46)
      ..cubicTo(92, 24, 70, 20, 50, 46)
      ..close()
      ..moveTo(46, 52)
      ..lineTo(34, 86)
      ..moveTo(54, 52)
      ..lineTo(66, 86), fill: _pink);
    _doodle(c, s, () => Path()..addOval(Rect.fromCircle(center: const Offset(50, 48), radius: 6)), fill: _pink);
  }),
  StickerDef('doodle_hearts', StickerCategory.doodle, 180, 160, (c, s) {
    Path small(double dx, double dy, double k) => _heart().transform((Matrix4.identity()
          ..translateByDouble(dx, dy, 0, 1)
          ..scaleByDouble(k, k, 1, 1))
        .storage);
    _doodle(c, s, () => small(4, 20, 0.6), fill: _pink);
    _doodle(c, s, () => small(52, 6, 0.42), fill: _lilac);
    _doodle(c, s, () => small(58, 58, 0.34), fill: _pink);
  }),
];
