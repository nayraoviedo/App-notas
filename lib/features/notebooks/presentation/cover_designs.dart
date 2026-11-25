import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/fonts.dart';
import '../../../core/widgets/cat_mascot.dart';
import '../domain/notebook.dart';

/// Portadas ilustradas (dibujadas por la app, al estilo de los cuadernos
/// "aesthetic"): flores sobre salvia, enrejado con flores azules, cuadros
/// con tulipanes y cielo con estrellas y gatito.
void paintIllustratedCover(Canvas canvas, Size size, CoverPattern pattern, Color base) {
  canvas.drawRect(Offset.zero & size, Paint()..color = base);
  switch (pattern) {
    case CoverPattern.sageFlowers:
      _sageFlowers(canvas, size, base);
    case CoverPattern.blueTrellis:
      _blueTrellis(canvas, size);
    case CoverPattern.tulipChecker:
      _tulipChecker(canvas, size);
    case CoverPattern.starryCat:
      _starryCat(canvas, size);
    default:
      break;
  }
}

/// Textura suave de papel (vetas finas).
void _texture(Canvas c, Size s, Color tint, {int seed = 1, bool vertical = true}) {
  final rnd = math.Random(seed);
  final p = Paint()
    ..color = tint
    ..strokeWidth = 0.6;
  for (var i = 0; i < (vertical ? s.width : s.height) / 3; i++) {
    final x = rnd.nextDouble() * (vertical ? s.width : s.height);
    final y0 = rnd.nextDouble() * (vertical ? s.height : s.width);
    final len = 10 + rnd.nextDouble() * 40;
    if (vertical) {
      c.drawLine(Offset(x, y0), Offset(x, y0 + len), p);
    } else {
      c.drawLine(Offset(y0, x), Offset(y0 + len, x), p);
    }
  }
}

void _flower(Canvas c, Offset at, double r, Color petal, Color center, {int petals = 5, double rot = 0}) {
  final p = Paint()..color = petal;
  for (var i = 0; i < petals; i++) {
    final a = rot + i * 2 * math.pi / petals;
    c.drawOval(
      Rect.fromCenter(center: at + Offset(math.cos(a), math.sin(a)) * r * 0.62, width: r * 0.95, height: r * 0.95),
      p,
    );
  }
  c.drawCircle(at, r * 0.25, Paint()..color = center);
}

// --------------------------------------------------- Salvia con florecitas

void _sageFlowers(Canvas c, Size s, Color base) {
  _texture(c, s, Colors.white.withValues(alpha: 0.12));
  final rnd = math.Random(11);
  final u = s.width / 10;
  final stem = Paint()
    ..color = const Color(0xFF7E9A6A)
    ..strokeWidth = u * 0.05
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 26; i++) {
    final root = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
    final n = 3 + rnd.nextInt(4);
    for (var k = 0; k < n; k++) {
      final a = -math.pi / 2 + (rnd.nextDouble() - 0.5) * 1.6;
      final len = u * (0.8 + rnd.nextDouble() * 0.9);
      final tip = root + Offset(math.cos(a), math.sin(a)) * len;
      c.drawPath(
        Path()
          ..moveTo(root.dx, root.dy)
          ..quadraticBezierTo((root.dx + tip.dx) / 2 + u * 0.1, (root.dy + tip.dy) / 2, tip.dx, tip.dy),
        stem,
      );
      _flower(c, tip, u * (0.32 + rnd.nextDouble() * 0.1), const Color(0xFFFBFBF6), const Color(0xFFE7D9A0),
          rot: rnd.nextDouble());
    }
    // Hojitas
    for (var k = 0; k < 2; k++) {
      final a = math.pi / 2 + (rnd.nextDouble() - 0.5) * 2;
      c.drawLine(root, root + Offset(math.cos(a), math.sin(a)) * u * 0.5, stem);
    }
  }
}

// ---------------------------------------- Enrejado con flores azules

void _blueTrellis(Canvas c, Size s) {
  final cw = s.width / 3.2;
  final ch = cw * 1.3;
  final stitch = Paint()
    ..color = const Color(0xFF8C9199)
    ..strokeWidth = 1
    ..strokeCap = StrokeCap.round;
  // Rombos con puntadas cortas.
  for (var row = -1; row < s.height / ch + 2; row++) {
    for (var col = -1; col < s.width / cw + 2; col++) {
      final cx = col * cw + (row.isOdd ? cw / 2 : 0);
      final cy = row * ch / 2;
      final pts = [
        Offset(cx, cy - ch / 2),
        Offset(cx + cw / 2, cy),
        Offset(cx, cy + ch / 2),
        Offset(cx - cw / 2, cy),
      ];
      for (var e = 0; e < 4; e++) {
        final a = pts[e], b = pts[(e + 1) % 4];
        for (var t = 0.05; t < 1; t += 0.11) {
          final p = Offset.lerp(a, b, t)!;
          c.drawLine(p, p + const Offset(1.6, -2.4), stitch);
        }
      }
    }
  }
  // Una flor en cada rombo.
  const blue = Color(0xFF7D98D3), lav = Color(0xFF9C9BDB), leaf = Color(0xFF6FA07A);
  var k = 0;
  for (var row = 0; row < s.height / (ch / 2) + 1; row++) {
    for (var col = 0; col < s.width / cw + 1; col++) {
      final at = Offset(col * cw + (row.isOdd ? 0 : cw / 2), row * ch / 2);
      final u = cw * 0.16;
      final stemP = Paint()
        ..color = leaf
        ..strokeWidth = 1.4;
      switch (k++ % 4) {
        case 0: // tulipán
          c.drawLine(at + Offset(0, -u * 0.2), at + Offset(0, u * 2), stemP);
          c.drawOval(Rect.fromCenter(center: at + Offset(0, -u * 0.6), width: u * 1.2, height: u * 1.5),
              Paint()..color = blue);
          c.drawOval(Rect.fromCenter(center: at + Offset(u * 0.5, u * 1.2), width: u * 0.5, height: u * 1.4),
              Paint()..color = leaf);
        case 1: // jacinto
          c.drawLine(at + Offset(0, -u), at + Offset(0, u * 2), stemP);
          for (var i = 0; i < 6; i++) {
            c.drawCircle(at + Offset((i.isEven ? -1 : 1) * u * 0.25, -u * 1.2 + i * u * 0.35), u * 0.28,
                Paint()..color = lav);
          }
        case 2: // flor abierta
          c.drawLine(at, at + Offset(0, u * 2.1), stemP);
          _flower(c, at, u * 0.95, blue, Colors.white, petals: 6);
        default: // campanitas
          c.drawPath(
              Path()
                ..moveTo(at.dx, at.dy + u * 2)
                ..quadraticBezierTo(at.dx - u * 0.2, at.dy - u, at.dx + u * 0.8, at.dy - u * 1.2),
              stemP..style = PaintingStyle.stroke);
          for (var i = 0; i < 3; i++) {
            c.drawPath(
              Path()
                ..addArc(
                    Rect.fromCenter(center: at + Offset(u * 0.6 - i * u * 0.5, -u * 0.6 + i * u * 0.6),
                        width: u * 0.8, height: u * 0.9),
                    math.pi, math.pi),
              Paint()..color = const Color(0xFF9DB3E0),
            );
          }
      }
    }
  }
}

// --------------------------------- Cuadros azul y crema con tulipanes

void _tulipChecker(Canvas c, Size s) {
  const blue = Color(0xFFC6D1DE), cream = Color(0xFFF6F0E4);
  final cell = s.width / 4.4;
  for (var r = 0; r * cell < s.height; r++) {
    for (var col = 0; col * cell < s.width; col++) {
      final rect = Rect.fromLTWH(col * cell, r * cell, cell, cell);
      final isBlue = (r + col).isOdd;
      c.drawRect(rect, Paint()..color = isBlue ? blue : cream);
      final ctr = rect.center;
      final u = cell / 6;
      if (!isBlue && (r * 3 + col) % 4 == 1) {
        // Tulipán rosado
        final stem = Paint()
          ..color = const Color(0xFF7D8E97)
          ..strokeWidth = u * 0.35
          ..strokeCap = StrokeCap.round;
        c.drawLine(ctr + Offset(0, -u * 0.2), ctr + Offset(u * 0.4, u * 2.2), stem);
        c.drawLine(ctr + Offset(u * 0.2, u * 1.2), ctr + Offset(u * 1.1, u * 0.7), stem);
        c.drawOval(Rect.fromCenter(center: ctr + Offset(0, -u * 0.8), width: u * 2.1, height: u * 2.2),
            Paint()..color = const Color(0xFFEE9C9A));
        c.drawOval(Rect.fromCenter(center: ctr + Offset(-u * 0.4, -u * 0.9), width: u * 0.9, height: u * 1.6),
            Paint()..color = const Color(0xFFF4B5B0));
      } else if (isBlue && (r + col * 2) % 5 == 0) {
        // Carita de gatito blanca
        final head = Rect.fromCenter(center: ctr, width: u * 4, height: u * 3.2);
        final ear = Paint()..color = Colors.white;
        for (final f in [-1.0, 1.0]) {
          c.drawPath(
              Path()
                ..moveTo(ctr.dx + f * u * 1.9, ctr.dy - u * 0.4)
                ..lineTo(ctr.dx + f * u * 1.5, ctr.dy - u * 2.1)
                ..lineTo(ctr.dx + f * u * 0.6, ctr.dy - u * 1.3)
                ..close(),
              ear);
        }
        c.drawRRect(RRect.fromRectAndRadius(head, Radius.circular(u * 1.4)), Paint()..color = Colors.white);
        c.drawRRect(
            RRect.fromRectAndRadius(head, Radius.circular(u * 1.4)),
            Paint()
              ..color = const Color(0xFF55627A)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2);
        final ink = Paint()..color = const Color(0xFF2E3440);
        c.drawCircle(ctr + Offset(-u * 0.8, -u * 0.1), u * 0.2, ink);
        c.drawCircle(ctr + Offset(u * 0.8, -u * 0.1), u * 0.2, ink);
        c.drawCircle(ctr + Offset(0, u * 0.35), u * 0.12, ink);
        final blush = Paint()..color = const Color(0x66F29AA3);
        c.drawOval(Rect.fromCenter(center: ctr + Offset(-u * 1.3, u * 0.4), width: u * 0.8, height: u * 0.4), blush);
        c.drawOval(Rect.fromCenter(center: ctr + Offset(u * 1.3, u * 0.4), width: u * 0.8, height: u * 0.4), blush);
      }
    }
  }
  _texture(c, s, Colors.white.withValues(alpha: 0.25), seed: 4, vertical: false);
}

// ------------------------------------- Cielo crema con estrellas y gatito

void _starryCat(Canvas c, Size s) {
  final w = s.width, h = s.height;
  final rnd = math.Random(8);
  final speck = Paint()..color = const Color(0x14000000);
  for (var i = 0; i < 160; i++) {
    c.drawCircle(Offset(rnd.nextDouble() * w, rnd.nextDouble() * h), 0.7, speck);
  }
  // Planeta con anillo.
  final pc = Offset(w * 0.8, h * 0.18), pr = w * 0.09;
  c.drawCircle(pc, pr, Paint()..color = const Color(0xFFBFC7E3));
  for (var i = -1; i <= 1; i++) {
    c.drawArc(Rect.fromCircle(center: pc + Offset(0, i * pr * 0.45), radius: pr * 0.95), 0.2, math.pi - 0.4,
        false,
        Paint()
          ..color = const Color(0xFFF1D7A5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = pr * 0.18);
  }
  c.drawOval(
      Rect.fromCenter(center: pc, width: pr * 3.2, height: pr * 0.8),
      Paint()
        ..color = const Color(0xFF2E3440)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6);
  // Estrellitas.
  final starFill = Paint()..color = const Color(0xFFF3C35A);
  final starLine = Paint()
    ..color = const Color(0xFF3B3B3B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  for (final (fx, fy, fr) in [
    (0.2, 0.12, 0.03), (0.72, 0.06, 0.025), (0.14, 0.33, 0.045), (0.55, 0.48, 0.035), (0.33, 0.9, 0.02),
    (0.9, 0.6, 0.02), (0.42, 0.04, 0.015),
  ]) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = (i.isEven ? fr : fr * 0.45) * w;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(fx * w + math.cos(a) * r, fy * h + math.sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    c.drawPath(path, starFill);
    c.drawPath(path, starLine);
  }
  // Destellos.
  final spark = Paint()
    ..color = const Color(0xFFC98A8A)
    ..strokeWidth = 1;
  for (final (fx, fy) in [(0.3, 0.06), (0.88, 0.3), (0.08, 0.8), (0.62, 0.62)]) {
    final p = Offset(fx * w, fy * h);
    c.drawLine(p + const Offset(-4, 0), p + const Offset(4, 0), spark);
    c.drawLine(p + const Offset(0, -4), p + const Offset(0, 4), spark);
  }
  // Superficie del planeta abajo con manchas pastel.
  final ground = Path()
    ..moveTo(0, h * 0.52)
    ..quadraticBezierTo(w * 0.55, h * 0.58, w * 0.68, h)
    ..lineTo(0, h)
    ..close();
  c.save();
  c.clipPath(ground);
  c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF4E6CF));
  c.drawCircle(Offset(w * 0.25, h * 0.75), w * 0.22, Paint()..color = const Color(0x55F7D98B));
  c.drawCircle(Offset(w * 0.1, h * 0.95), w * 0.18, Paint()..color = const Color(0x55B9C3E6));
  c.drawCircle(Offset(w * 0.3, h * 0.62), w * 0.03, Paint()..color = const Color(0xFFAEB7CF));
  c.restore();
  c.drawPath(
      Path()
        ..moveTo(0, h * 0.52)
        ..quadraticBezierTo(w * 0.55, h * 0.58, w * 0.68, h),
      Paint()
        ..color = const Color(0xFFB38E8E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4);
  // Gatito asomándose.
  final catW = w * 0.34;
  c.save();
  c.translate(w * 0.46, h * 0.64);
  CatPainter(CatKind.gray).paint(c, Size(catW, catW * 1.1));
  c.restore();
  final tp = TextPainter(
    text: TextSpan(text: 'Miau ~', style: TextStyle(fontSize: w * 0.045, color: const Color(0xFF2E3440))),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset(w * 0.78, h * 0.7));
}

/// Placa central "NOTEBOOK" con renglones, como en los cuadernos de papelería.
class CoverPlate extends StatelessWidget {
  const CoverPlate({super.key, required this.title, required this.width, required this.tint});
  final String title;
  final double width;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(tint);
    final ink = hsl.withLightness((hsl.lightness * 0.6).clamp(0.2, 0.55)).toColor();
    return Container(
      width: width * 0.32,
      padding: EdgeInsets.all(width * 0.012),
      decoration: BoxDecoration(
        color: Color.lerp(tint, Colors.white, 0.82),
        border: Border.all(color: ink.withValues(alpha: 0.35), width: 1),
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(width * 0.02, width * 0.03, width * 0.02, width * 0.035),
        decoration: BoxDecoration(border: Border.all(color: ink.withValues(alpha: 0.25), width: 0.6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              child: Text(
                (title.isEmpty ? 'Notebook' : title).toUpperCase(),
                maxLines: 1,
                style: fontStyle('Playfair Display', size: width * 0.045)
                    .copyWith(color: ink, fontWeight: FontWeight.w700),
              ),
            ),
            for (var i = 0; i < 3; i++)
              Container(
                height: 1,
                margin: EdgeInsets.only(top: width * 0.028),
                color: ink.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }
}

/// Placa central dibujada en la tapa de una nota (el título va encima como
/// texto editable).
void paintPlateBox(Canvas c, Size s, Color tint) {
  final hsl = HSLColor.fromColor(tint);
  final ink = hsl.withLightness((hsl.lightness * 0.6).clamp(0.2, 0.55)).toColor();
  final r = Rect.fromLTRB(s.width * 0.28, s.height * 0.16, s.width * 0.72, s.height * 0.43);
  c.drawRect(r, Paint()..color = Color.lerp(tint, Colors.white, 0.85)!);
  final border = Paint()
    ..color = ink.withValues(alpha: 0.4)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  c.drawRect(r, border);
  c.drawRect(r.deflate(s.width * 0.012), border..strokeWidth = 1);
  final line = Paint()
    ..color = ink.withValues(alpha: 0.5)
    ..strokeWidth = 1.5;
  for (var i = 0; i < 3; i++) {
    final y = r.top + r.height * (0.55 + i * 0.13);
    c.drawLine(Offset(r.left + r.width * 0.1, y), Offset(r.right - r.width * 0.1, y), line);
  }
}
