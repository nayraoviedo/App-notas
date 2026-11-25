import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Las mascotas de la app, inspiradas en los gatitos de la casa:
/// - [CatKind.orange]: atigrado naranja, ojos ámbar y chaleco oscuro.
/// - [CatKind.gray]: gris con pecho blanco, ojos dorados y collar verde.
enum CatKind { orange, gray }

class _CatColors {
  const _CatColors({
    required this.fur,
    required this.furDark,
    required this.light,
    required this.eye,
    required this.outline,
  });
  final Color fur;
  final Color furDark;
  final Color light;
  final Color eye;
  final Color outline;
}

const _orange = _CatColors(
  fur: Color(0xFFF3B36E),
  furDark: Color(0xFFDE8A45),
  light: Color(0xFFFBE3C2),
  eye: Color(0xFFE9B23A),
  outline: Color(0xFF8A5530),
);

const _gray = _CatColors(
  fur: Color(0xFFA3A8B3),
  furDark: Color(0xFF858B97),
  light: Color(0xFFFFFFFF),
  eye: Color(0xFFD1B14A),
  outline: Color(0xFF5B606B),
);

/// Gatito sentado estilo chibi. [blink] cierra los ojos (para animarlo).
class CatMascot extends StatelessWidget {
  const CatMascot({super.key, this.kind = CatKind.orange, this.size = 120, this.blink = false});
  final CatKind kind;
  final double size;
  final bool blink;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size * 1.1,
        child: CustomPaint(painter: CatPainter(kind, blink: blink)),
      );
}

/// Gatito que respira y parpadea solo.
class AnimatedCatMascot extends StatefulWidget {
  const AnimatedCatMascot({super.key, this.kind = CatKind.orange, this.size = 120, this.onTap});
  final CatKind kind;
  final double size;
  final VoidCallback? onTap;

  @override
  State<AnimatedCatMascot> createState() => _AnimatedCatMascotState();
}

class _AnimatedCatMascotState extends State<AnimatedCatMascot> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(seconds: 4))
    ..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final t = _anim.value;
          final bob = math.sin(t * math.pi * 2) * 2.5;
          final blink = t > 0.9 && t < 0.94;
          return Transform.translate(
            offset: Offset(0, bob),
            child: CatMascot(kind: widget.kind, size: widget.size, blink: blink),
          );
        },
      ),
    );
  }
}

class CatPainter extends CustomPainter {
  const CatPainter(this.kind, {this.blink = false});
  final CatKind kind;
  final bool blink;

  @override
  void paint(Canvas canvas, Size size) {
    // Se dibuja en una caja de 200 × 220 y se escala.
    canvas.save();
    canvas.scale(size.width / 200, size.height / 220);
    final c = kind == CatKind.orange ? _orange : _gray;
    final line = Paint()
      ..color = c.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Paint fill(Color col) => Paint()..color = col;

    // Sombra en el piso.
    canvas.drawOval(Rect.fromCenter(center: const Offset(100, 212), width: 130, height: 14),
        fill(Colors.black.withValues(alpha: 0.08)));

    // Cola.
    final tail = Path()
      ..moveTo(140, 200)
      ..quadraticBezierTo(195, 195, 182, 150)
      ..quadraticBezierTo(176, 130, 188, 118);
    canvas.drawPath(tail, line..strokeWidth = 17);
    canvas.drawPath(
        tail,
        Paint()
          ..color = c.fur
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round);
    line.strokeWidth = 3;
    if (kind == CatKind.orange) {
      final stripe = Paint()
        ..color = c.furDark
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(178, 168), const Offset(190, 164), stripe);
      canvas.drawLine(const Offset(180, 146), const Offset(191, 148), stripe);
    }

    // Cuerpo.
    final body = Rect.fromCenter(center: const Offset(100, 168), width: 118, height: 92);
    canvas.drawOval(body, fill(c.fur));
    if (kind == CatKind.gray) {
      // Pecho blanco.
      canvas.drawOval(Rect.fromCenter(center: const Offset(100, 168), width: 64, height: 80),
          fill(c.light));
    } else {
      final stripe = Paint()
        ..color = c.furDark
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(48, 160), const Offset(58, 166), stripe);
      canvas.drawLine(const Offset(152, 160), const Offset(142, 166), stripe);
    }
    canvas.drawOval(body, line);

    // Chaleco (naranja) o collar (gris).
    if (kind == CatKind.orange) {
      final vest = Path()
        ..moveTo(50, 150)
        ..quadraticBezierTo(100, 128, 150, 150)
        ..quadraticBezierTo(160, 178, 150, 196)
        ..quadraticBezierTo(100, 206, 50, 196)
        ..quadraticBezierTo(40, 178, 50, 150)
        ..close();
      canvas.save();
      canvas.clipPath(Path()..addOval(body));
      canvas.drawPath(vest, fill(const Color(0xFF2E3340)));
      final seam = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 2;
      canvas.drawLine(const Offset(60, 172), const Offset(140, 172), seam);
      canvas.drawLine(const Offset(62, 186), const Offset(138, 186), seam);
      canvas.restore();
    }

    // Patitas.
    for (final x in [78.0, 122.0]) {
      final paw = Rect.fromCenter(center: Offset(x, 203), width: 30, height: 20);
      canvas.drawOval(paw, fill(kind == CatKind.gray ? c.light : c.fur));
      canvas.drawOval(paw, line);
      canvas.drawLine(Offset(x - 4, 197), Offset(x - 4, 203), line..strokeWidth = 2);
      canvas.drawLine(Offset(x + 4, 197), Offset(x + 4, 203), line);
      line.strokeWidth = 3;
    }

    // Orejas.
    for (final flip in [false, true]) {
      double fx(double x) => flip ? 200 - x : x;
      final ear = Path()
        ..moveTo(fx(38), 78)
        ..quadraticBezierTo(fx(30), 22, fx(46), 14)
        ..quadraticBezierTo(fx(62), 14, fx(92), 44)
        ..close();
      canvas.drawPath(ear, fill(c.fur));
      canvas.drawPath(ear, line);
      final inner = Path()
        ..moveTo(fx(46), 62)
        ..quadraticBezierTo(fx(42), 30, fx(50), 26)
        ..quadraticBezierTo(fx(60), 28, fx(78), 46)
        ..close();
      canvas.drawPath(inner, fill(const Color(0xFFF7B9B9)));
    }

    // Cabeza.
    final head = Rect.fromCenter(center: const Offset(100, 92), width: 160, height: 124);
    canvas.drawOval(head, fill(c.fur));
    canvas.save();
    canvas.clipPath(Path()..addOval(head));
    if (kind == CatKind.gray) {
      // Antifaz blanco: hocico y franja entre los ojos.
      final mask = Path()
        ..moveTo(100, 58)
        ..quadraticBezierTo(112, 80, 132, 104)
        ..quadraticBezierTo(150, 140, 100, 150)
        ..quadraticBezierTo(50, 140, 68, 104)
        ..quadraticBezierTo(88, 80, 100, 58)
        ..close();
      canvas.drawPath(mask, fill(c.light));
    } else {
      // Hocico claro.
      canvas.drawOval(Rect.fromCenter(center: const Offset(100, 122), width: 76, height: 46),
          fill(c.light));
      // Rayitas en la frente ("M" del atigrado) y en las mejillas.
      final stripe = Paint()
        ..color = c.furDark
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(100, 34), const Offset(100, 52), stripe);
      canvas.drawLine(const Offset(86, 38), const Offset(90, 54), stripe);
      canvas.drawLine(const Offset(114, 38), const Offset(110, 54), stripe);
      for (final y in [96.0, 108.0]) {
        canvas.drawLine(Offset(20, y), Offset(36, y + 2), stripe);
        canvas.drawLine(Offset(180, y), Offset(164, y + 2), stripe);
      }
    }
    canvas.restore();
    canvas.drawOval(head, line);

    // Ojos.
    for (final x in [70.0, 130.0]) {
      if (blink) {
        canvas.drawArc(Rect.fromCenter(center: Offset(x, 96), width: 22, height: 12), 0.2,
            math.pi - 0.4, false, line);
        continue;
      }
      canvas.drawOval(Rect.fromCenter(center: Offset(x, 94), width: 26, height: 28), fill(c.eye));
      canvas.drawOval(Rect.fromCenter(center: Offset(x, 95), width: 15, height: 22),
          fill(const Color(0xFF2A2320)));
      canvas.drawCircle(Offset(x + 4, 88), 4.5, fill(Colors.white));
      canvas.drawCircle(Offset(x - 4, 101), 2, fill(Colors.white));
      canvas.drawOval(Rect.fromCenter(center: Offset(x, 94), width: 26, height: 28),
          line..strokeWidth = 2);
      line.strokeWidth = 3;
    }

    // Cachetes.
    for (final x in [50.0, 150.0]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x, 118), width: 22, height: 12),
          fill(const Color(0xFFF6A1A6).withValues(alpha: 0.6)));
    }

    // Nariz y boquita.
    final nose = Path()
      ..moveTo(93, 112)
      ..quadraticBezierTo(100, 108, 107, 112)
      ..quadraticBezierTo(102, 120, 100, 120)
      ..quadraticBezierTo(98, 120, 93, 112)
      ..close();
    canvas.drawPath(nose, fill(const Color(0xFFF29AA3)));
    final mouth = Path()
      ..moveTo(100, 120)
      ..lineTo(100, 125)
      ..moveTo(88, 124)
      ..quadraticBezierTo(94, 132, 100, 125)
      ..quadraticBezierTo(106, 132, 112, 124);
    canvas.drawPath(mouth, line..strokeWidth = 2.4);

    // Bigotes.
    final whisker = Paint()
      ..color = c.outline.withValues(alpha: 0.55)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final (dy, ang) in [(-4.0, -0.12), (3.0, 0.08)]) {
      canvas.drawLine(Offset(70, 120 + dy), Offset(36, 116 + dy + ang * 80), whisker);
      canvas.drawLine(Offset(130, 120 + dy), Offset(164, 116 + dy + ang * 80), whisker);
    }

    // Collar verde con argolla (gris).
    if (kind == CatKind.gray) {
      final collar = Path()
        ..moveTo(60, 146)
        ..quadraticBezierTo(100, 162, 140, 146);
      canvas.drawPath(
          collar,
          Paint()
            ..color = const Color(0xFF2FA866)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.round);
      canvas.drawCircle(const Offset(100, 162), 6,
          Paint()
            ..color = const Color(0xFFC9CED6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CatPainter old) => old.kind != kind || old.blink != blink;
}

/// Frases de las mascotas.
const catPhrases = [
  '¡Hola! ¿Qué escribimos hoy?',
  'Miau~ no olvides tomar agua 💧',
  '¡Tú puedes! Un poquito cada día 📚',
  'Hoy es un buen día para tu diario ✨',
  '¿Repasamos tus notas? 🐾',
  'Me encanta cuando dibujas 🎨',
  'Respira hondo… y a escribir 🌸',
];
