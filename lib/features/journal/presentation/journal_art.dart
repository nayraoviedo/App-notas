import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/journal.dart';
import '../../../core/widgets/doodle_icon.dart';

/// Dibujos propios del diario: las nubecitas-gato de los ánimos ("kumo" es
/// nube en japonés) y los paisajes de hábitos y del calendario.
/// Todo se pinta con código: no hay imágenes de otras apps.

const _ink = Color(0xFF3B2A22);
const _blush = Color(0x66F2879A);

/// Silueta de nube con orejitas de gato, en una caja de 100 × 100.
Path kumoCloudPath() {
  var p = Path();
  for (final (x, y, r) in const [
    (50.0, 58.0, 33.0),
    (28.0, 64.0, 21.0),
    (72.0, 64.0, 21.0),
    (37.0, 42.0, 21.0),
    (63.0, 42.0, 21.0),
    (50.0, 72.0, 24.0),
  ]) {
    p = Path.combine(PathOperation.union, p, Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r)));
  }
  for (final flip in [false, true]) {
    double fx(double x) => flip ? 100 - x : x;
    final ear = Path()
      ..moveTo(fx(20), 38)
      ..quadraticBezierTo(fx(19), 14, fx(26), 9)
      ..quadraticBezierTo(fx(33), 9, fx(44), 26)
      ..close();
    p = Path.combine(PathOperation.union, p, ear);
  }
  return p;
}

final Path _cloud = kumoCloudPath();

/// Color de cada ánimo (cuerpo de la nube) y su tono más oscuro (borde).
(Color, Color) moodColors(Mood m) => switch (m) {
      Mood.great => (const Color(0xFFFFD66B), const Color(0xFFE9A93A)),
      Mood.good => (const Color(0xFFB5E0A0), const Color(0xFF76B05E)),
      Mood.meh => (const Color(0xFFFFF4E2), const Color(0xFFD9C3A5)),
      Mood.sad => (const Color(0xFFAED3F2), const Color(0xFF6E9FCB)),
      Mood.angry => (const Color(0xFFF7AFA4), const Color(0xFFD96F62)),
      Mood.tired => (const Color(0xFFD5C3F0), const Color(0xFF9B83C7)),
    };

/// La carita de un ánimo. Si [mood] es null se ve un circulito vacío.
class MoodFace extends StatelessWidget {
  const MoodFace({super.key, required this.mood, this.size = 44, this.faded = false});
  final Mood? mood;
  final double size;

  /// Días que aún no llegan: más transparentes.
  final bool faded;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MoodFacePainter(mood, faded)),
      );
}

class _MoodFacePainter extends CustomPainter {
  const _MoodFacePainter(this.mood, this.faded);
  final Mood? mood;
  final bool faded;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final m = mood;
    if (m == null) {
      canvas.drawCircle(const Offset(50, 54), 38,
          Paint()..color = Colors.white.withValues(alpha: faded ? 0.35 : 0.6));
      canvas.restore();
      return;
    }
    final (body, edge) = moodColors(m);
    Paint fill(Color c) => Paint()..color = c;
    final line = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Sombrita, cuerpo, brillo y borde.
    canvas.drawPath(_cloud.shift(const Offset(0, 3)), fill(edge.withValues(alpha: 0.35)));
    canvas.drawPath(_cloud, fill(body));
    canvas.save();
    canvas.clipPath(_cloud);
    canvas.drawOval(const Rect.fromLTWH(18, 26, 40, 22), fill(Colors.white.withValues(alpha: 0.35)));
    canvas.drawOval(const Rect.fromLTWH(-10, 80, 120, 40), fill(edge.withValues(alpha: 0.25)));
    canvas.restore();
    canvas.drawPath(
        _cloud,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6);
    // Adentro de las orejas.
    for (final flip in [false, true]) {
      double fx(double x) => flip ? 100 - x : x;
      final inner = Path()
        ..moveTo(fx(25), 30)
        ..quadraticBezierTo(fx(25), 18, fx(28), 15)
        ..quadraticBezierTo(fx(33), 16, fx(38), 25)
        ..close();
      canvas.drawPath(inner, fill(const Color(0xFFF6B3BE)));
    }

    // Cachetes.
    if (m != Mood.angry) {
      for (final x in [30.0, 70.0]) {
        canvas.drawOval(Rect.fromCenter(center: Offset(x, 68), width: 14, height: 8), fill(_blush));
      }
    }

    void dotEyes({double y = 58}) {
      for (final x in [39.0, 61.0]) {
        canvas.drawCircle(Offset(x, y), 4, fill(_ink));
        canvas.drawCircle(Offset(x + 1.3, y - 1.4), 1.3, fill(Colors.white));
      }
    }

    switch (m) {
      case Mood.great:
        for (final x in [39.0, 61.0]) {
          canvas.drawArc(Rect.fromCenter(center: Offset(x, 60), width: 12, height: 10), math.pi + 0.2,
              math.pi - 0.4, false, line);
        }
        final mouth = Path()
          ..moveTo(41, 66)
          ..quadraticBezierTo(50, 66, 59, 66)
          ..quadraticBezierTo(58, 80, 50, 80)
          ..quadraticBezierTo(42, 80, 41, 66)
          ..close();
        canvas.drawPath(mouth, fill(_ink));
        canvas.save();
        canvas.clipPath(mouth);
        canvas.drawCircle(const Offset(50, 82), 6, fill(const Color(0xFFF2788A)));
        canvas.restore();
        _sparkle(canvas, const Offset(86, 22), 7, Colors.white);
        _sparkle(canvas, const Offset(13, 24), 5, Colors.white);
      case Mood.good:
        dotEyes();
        canvas.drawArc(const Rect.fromLTWH(43, 61, 14, 10), 0.25, math.pi - 0.5, false, line);
      case Mood.meh:
        dotEyes();
        canvas.drawLine(const Offset(45, 69), const Offset(55, 69), line);
      case Mood.sad:
        dotEyes(y: 60);
        for (final (x, dir) in [(37.0, 1.0), (63.0, -1.0)]) {
          canvas.drawLine(Offset(x - 5 * dir, 50), Offset(x + 4 * dir, 47), line..strokeWidth = 2.8);
        }
        line.strokeWidth = 3.6;
        canvas.drawArc(const Rect.fromLTWH(43, 68, 14, 10), math.pi + 0.35, math.pi - 0.7, false, line);
        final tear = Path()
          ..moveTo(33, 63)
          ..quadraticBezierTo(28, 71, 31, 74)
          ..quadraticBezierTo(35, 76, 36, 71)
          ..quadraticBezierTo(36, 68, 33, 63)
          ..close();
        canvas.drawPath(tear, fill(const Color(0xFF5BA4E0)));
      case Mood.angry:
        dotEyes(y: 60);
        for (final (x, dir) in [(37.0, 1.0), (63.0, -1.0)]) {
          canvas.drawLine(Offset(x - 6 * dir, 48), Offset(x + 5 * dir, 53), line..strokeWidth = 3.2);
        }
        line.strokeWidth = 3.6;
        canvas.drawArc(const Rect.fromLTWH(43, 68, 14, 9), math.pi + 0.35, math.pi - 0.7, false, line);
        for (final x in [30.0, 70.0]) {
          canvas.drawOval(Rect.fromCenter(center: Offset(x, 68), width: 14, height: 8),
              fill(const Color(0x88E2574C)));
        }
        // Venita de enojo.
        final vein = Paint()
          ..color = const Color(0xFFE2574C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        const c = Offset(84, 24);
        for (var i = 0; i < 4; i++) {
          final a = i * math.pi / 2 + math.pi / 4;
          final o = c + Offset(math.cos(a), math.sin(a)) * 6;
          canvas.drawArc(Rect.fromCircle(center: o, radius: 4.5), a + math.pi - 0.8, 1.6, false, vein);
        }
      case Mood.tired:
        for (final x in [39.0, 61.0]) {
          canvas.drawArc(Rect.fromCenter(center: Offset(x, 57), width: 12, height: 8), 0.2, math.pi - 0.4,
              false, line);
        }
        canvas.drawOval(Rect.fromCenter(center: const Offset(50, 71), width: 7, height: 8), fill(_ink));
        final z = Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        for (final (o, s) in [(const Offset(80, 14), 9.0), (const Offset(91, 4), 6.0)]) {
          canvas.drawPath(
              Path()
                ..moveTo(o.dx, o.dy)
                ..lineTo(o.dx + s, o.dy)
                ..lineTo(o.dx, o.dy + s)
                ..lineTo(o.dx + s, o.dy + s),
              z);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MoodFacePainter old) => old.mood != mood || old.faded != faded;
}

/// Estrellita de cuatro puntas.
void _sparkle(Canvas canvas, Offset c, double r, Color color) {
  final p = Path()
    ..moveTo(c.dx, c.dy - r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
    ..close();
  canvas.drawPath(p, Paint()..color = color);
}

/// Nube-gato blanca para el cielo de los paisajes.
void _skyCloud(Canvas canvas, Offset topLeft, double width, {double alpha = 0.95}) {
  canvas.save();
  canvas.translate(topLeft.dx, topLeft.dy);
  canvas.scale(width / 100, width / 100 * 0.62);
  canvas.drawPath(_cloud, Paint()..color = Colors.white.withValues(alpha: alpha));
  canvas.restore();
}

// ------------------------------------------------------------------ Jardín

/// El jardín de arriba de los hábitos: cielo, colinas, árboles y florcitas
/// dormilonas. El gatito se pone encima como widget (así puede ser la foto).
class GardenScene extends StatelessWidget {
  const GardenScene({super.key, this.progress = 0});

  /// 0 a 1: cuántos hábitos de hoy están hechos. Con más avance, más flores
  /// abren los ojitos.
  final double progress;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GardenPainter(progress), size: Size.infinite);
}

/// Alto del paisaje del jardín dentro de un panel de [size].
double gardenBoxHeight(Size size) => math.min(size.height, size.width * 0.85);

class _GardenPainter extends CustomPainter {
  const _GardenPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    Paint fill(Color c) => Paint()..color = c;

    // Cielo.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFC9E9F6), Color(0xFFE9F6E4)],
        ).createShader(Offset.zero & size),
    );
    // El paisaje se dibuja en una caja de proporción fija pegada abajo
    // (en la compu el panel es alto: arriba queda más cielo).
    final h = gardenBoxHeight(size);
    final extraSky = size.height - h;
    if (extraSky > 60) {
      _skyCloud(canvas, Offset(w * 0.12, extraSky * 0.25), w * 0.22, alpha: 0.85);
      _skyCloud(canvas, Offset(w * 0.6, extraSky * 0.55), w * 0.16, alpha: 0.7);
      _sparkle(canvas, Offset(w * 0.45, extraSky * 0.3), 6, Colors.white);
    }
    canvas.save();
    canvas.translate(0, extraSky);
    // Sol.
    final sun = Offset(w * 0.84, h * 0.17);
    canvas.drawCircle(sun, h * 0.13, fill(const Color(0x33FFE08A)));
    canvas.drawCircle(sun, h * 0.085, fill(const Color(0xFFFFE08A)));
    _skyCloud(canvas, Offset(w * 0.06, h * 0.08), w * 0.2);
    _skyCloud(canvas, Offset(w * 0.55, h * 0.2), w * 0.14, alpha: 0.8);

    // Colinas de atrás y de adelante.
    final back = Path()
      ..moveTo(0, h * 0.52)
      ..quadraticBezierTo(w * 0.25, h * 0.36, w * 0.5, h * 0.48)
      ..quadraticBezierTo(w * 0.78, h * 0.6, w, h * 0.42)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, fill(const Color(0xFFBEDFA0)));

    // Árboles redonditos a los lados.
    for (final (x, y, r) in [(w * 0.07, h * 0.42, h * 0.16), (w * 0.95, h * 0.36, h * 0.19)]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x - r * 0.12, y, r * 0.24, h * 0.32), Radius.circular(r)),
          fill(const Color(0xFFA4785A)));
      canvas.drawCircle(Offset(x, y - r * 0.2), r, fill(const Color(0xFF86BF6C)));
      canvas.drawCircle(Offset(x - r * 0.55, y + r * 0.15), r * 0.65, fill(const Color(0xFF86BF6C)));
      canvas.drawCircle(Offset(x + r * 0.55, y + r * 0.1), r * 0.7, fill(const Color(0xFF7AB561)));
      canvas.drawCircle(Offset(x - r * 0.3, y - r * 0.5), r * 0.35, fill(const Color(0x33FFFFFF)));
    }

    final front = Path()
      ..moveTo(0, h * 0.7)
      ..quadraticBezierTo(w * 0.35, h * 0.58, w * 0.62, h * 0.66)
      ..quadraticBezierTo(w * 0.85, h * 0.72, w, h * 0.64)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, fill(const Color(0xFFA6D08A)));

    // Caminito.
    final path = Path()
      ..moveTo(w * 0.38, h)
      ..quadraticBezierTo(w * 0.46, h * 0.82, w * 0.56, h * 0.68)
      ..lineTo(w * 0.62, h * 0.68)
      ..quadraticBezierTo(w * 0.58, h * 0.84, w * 0.64, h)
      ..close();
    canvas.drawPath(path, fill(const Color(0xFFF1DDB4)));

    // Matitas de pasto.
    final grass = Paint()
      ..color = const Color(0xFF7DB563)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (final (x, y) in [(0.2, 0.86), (0.33, 0.74), (0.74, 0.82), (0.88, 0.9), (0.08, 0.95)]) {
      final o = Offset(w * x, h * y);
      canvas.drawLine(o, o + const Offset(-4, -9), grass);
      canvas.drawLine(o, o + const Offset(0, -12), grass);
      canvas.drawLine(o, o + const Offset(4, -9), grass);
    }

    // Florcitas con carita: abren los ojos según el avance del día.
    final unit = h / 260;
    final flowers = [
      (w * 0.2, h * 0.66, const Color(0xFFFFD66B), 1.15, 0.0),
      (w * 0.33, h * 0.6, const Color(0xFFF7AFC3), 0.9, 0.34),
      (w * 0.76, h * 0.64, const Color(0xFFD5C3F0), 1.0, 0.67),
      (w * 0.87, h * 0.78, const Color(0xFFFFFFFF), 0.8, 1.0),
    ];
    for (final (x, y, color, scale, need) in flowers) {
      _flower(canvas, Offset(x, y), color, unit * scale * 34, awake: progress > 0 && progress >= need);
    }
    // Brillitos.
    for (final (x, y, r) in [(0.27, 0.3, 6.0), (0.45, 0.22, 4.0), (0.68, 0.4, 5.0), (0.12, 0.56, 3.5)]) {
      _sparkle(canvas, Offset(w * x, h * y), r * unit, Colors.white);
    }
    canvas.restore();
  }

  void _flower(Canvas canvas, Offset c, Color petal, double r, {required bool awake}) {
    final stem = Paint()
      ..color = const Color(0xFF4E9A5A)
      ..strokeWidth = r * 0.16
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..quadraticBezierTo(c.dx + r * 0.2, c.dy + r * 1.4, c.dx, c.dy + r * 2.6),
        stem);
    final leaf = Paint()..color = const Color(0xFF5FAE69);
    for (final dir in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(c.dx + r * 0.1, c.dy + r * 1.7);
      canvas.rotate(dir * 0.7);
      canvas.drawOval(Rect.fromCenter(center: Offset(dir * r * 0.5, 0), width: r * 1.0, height: r * 0.42), leaf);
      canvas.restore();
    }
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * 0.62, r * 0.48, Paint()..color = petal);
    }
    canvas.drawCircle(c, r * 0.5, Paint()..color = const Color(0xFFFFB84D));
    final face = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round;
    for (final dx in [-0.18, 0.18]) {
      final eye = c + Offset(dx * r, -r * 0.04);
      if (awake) {
        canvas.drawCircle(eye, r * 0.06, Paint()..color = _ink);
      } else {
        canvas.drawArc(Rect.fromCenter(center: eye, width: r * 0.2, height: r * 0.14), 0.2, math.pi - 0.4, false,
            face);
      }
    }
    canvas.drawArc(Rect.fromCenter(center: c + Offset(0, r * 0.12), width: r * 0.2, height: r * 0.14), 0.2,
        math.pi - 0.4, false, face);
    canvas.drawCircle(c + Offset(-r * 0.32, r * 0.12), r * 0.07, Paint()..color = _blush);
    canvas.drawCircle(c + Offset(r * 0.32, r * 0.12), r * 0.07, Paint()..color = _blush);
  }

  @override
  bool shouldRepaint(_GardenPainter old) => old.progress != progress;
}

// ---------------------------------------------------------------- Pradera

/// Colores del cielo del calendario.
const skyTop = Color(0xFFBFE4F8);
const skyBottom = Color(0xFFE3F3FB);

/// La pradera de abajo del calendario: nubes-gato, colinas y florcitas.
class MeadowScene extends StatelessWidget {
  const MeadowScene({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _MeadowPainter(), size: Size.infinite);
}

class _MeadowPainter extends CustomPainter {
  const _MeadowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Paint fill(Color c) => Paint()..color = c;
    _skyCloud(canvas, Offset(-w * 0.04, h * 0.12), w * 0.34);
    _skyCloud(canvas, Offset(w * 0.62, h * 0.02), w * 0.3, alpha: 0.85);
    _skyCloud(canvas, Offset(w * 0.4, h * 0.3), w * 0.14, alpha: 0.7);

    final far = Path()
      ..moveTo(0, h * 0.62)
      ..quadraticBezierTo(w * 0.2, h * 0.48, w * 0.45, h * 0.6)
      ..quadraticBezierTo(w * 0.7, h * 0.46, w, h * 0.56)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(far, fill(const Color(0xFF9FCF86)));
    // Arbustos redondos sobre la colina.
    for (final (x, r) in [(0.08, 0.07), (0.16, 0.05), (0.84, 0.08), (0.93, 0.055)]) {
      canvas.drawCircle(Offset(w * x, h * 0.6), h * r * 1.6, fill(const Color(0xFF86BF6C)));
    }
    final near = Path()
      ..moveTo(0, h * 0.74)
      ..quadraticBezierTo(w * 0.5, h * 0.62, w, h * 0.76)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(near, fill(const Color(0xFFB7DE8E)));
    // Campo de florcitas (posiciones fijas para que no "bailen").
    final rnd = math.Random(7);
    for (var i = 0; i < 70; i++) {
      final x = rnd.nextDouble() * w;
      final y = h * (0.78 + rnd.nextDouble() * 0.22);
      final r = 1.6 + rnd.nextDouble() * 2.4;
      final color = [const Color(0xFFFFE07A), Colors.white, const Color(0xFFF7AFC3)][i % 3];
      for (var k = 0; k < 5; k++) {
        final a = k * math.pi * 2 / 5;
        canvas.drawCircle(Offset(x, y) + Offset(math.cos(a), math.sin(a)) * r, r * 0.8, fill(color));
      }
      canvas.drawCircle(Offset(x, y), r * 0.6, fill(const Color(0xFFFFB84D)));
    }
    for (final (x, y, r) in [(0.3, 0.2, 5.0), (0.55, 0.12, 3.5), (0.78, 0.4, 4.0), (0.12, 0.45, 3.0)]) {
      _sparkle(canvas, Offset(w * x, h * y), r, Colors.white);
    }
  }

  @override
  bool shouldRepaint(_MeadowPainter old) => false;
}

/// Fondo redondito (como una piedrita) para el ícono de cada hábito.
class HabitBadge extends StatelessWidget {
  const HabitBadge({super.key, required this.emoji, required this.color, this.size = 54});
  final String emoji;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _BlobPainter(color),
          child: Center(child: DoodleIcon(emoji, size: size * 0.6)),
        ),
      );
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Path()
      ..moveTo(w * 0.5, h * 0.02)
      ..cubicTo(w * 0.86, h * 0.0, w * 1.0, h * 0.2, w * 0.98, h * 0.52)
      ..cubicTo(w * 0.97, h * 0.86, w * 0.78, h * 1.0, w * 0.48, h * 0.98)
      ..cubicTo(w * 0.16, h * 0.97, w * 0.0, h * 0.8, w * 0.03, h * 0.48)
      ..cubicTo(w * 0.05, h * 0.16, w * 0.2, h * 0.04, w * 0.5, h * 0.02)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
    canvas.drawOval(Rect.fromLTWH(w * 0.18, h * 0.12, w * 0.34, h * 0.18),
        Paint()..color = Colors.white.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.color != color;
}

/// Colores pastel para los hábitos (según su lugar en la lista).
const habitColors = [
  Color(0xFFBFA6E8),
  Color(0xFF9CCBF0),
  Color(0xFFFFC98B),
  Color(0xFFA9DCA0),
  Color(0xFFF7AFC3),
  Color(0xFFFFE07A),
];
