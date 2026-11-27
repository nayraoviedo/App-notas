import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Las mascotas de la app, inspiradas en los gatitos de la casa:
/// - [CatKind.orange]: atigrado naranja, ojos ámbar y chaleco oscuro.
/// - [CatKind.gray]: gris con pecho blanco, ojos dorados y collar verde.
enum CatKind { orange, gray }

/// Fotos reales de los gatitos (si la persona las puso) y sus nombres.
final catPhotos = ValueNotifier<Map<CatKind, String>>(const {});
final catNames = ValueNotifier<Map<CatKind, String>>(const {});

/// Carga fotos y nombres guardados (se llama al abrir la app).
void loadCatPrefs(SharedPreferences p) {
  catPhotos.value = {
    for (final k in CatKind.values)
      if (p.getString('cat.photo.${k.name}') case final path?)
        if (File(path).existsSync()) k: path,
  };
  catNames.value = {
    for (final k in CatKind.values)
      if (p.getString('cat.name.${k.name}') case final name?) k: name,
  };
}

Future<void> setCatPhoto(SharedPreferences p, CatKind k, String? path) async {
  if (path == null) {
    await p.remove('cat.photo.${k.name}');
  } else {
    await p.setString('cat.photo.${k.name}', path);
  }
  loadCatPrefs(p);
}

Future<void> setCatName(SharedPreferences p, CatKind k, String? name) async {
  if (name == null || name.trim().isEmpty) {
    await p.remove('cat.name.${k.name}');
  } else {
    await p.setString('cat.name.${k.name}', name.trim());
  }
  loadCatPrefs(p);
}

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
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: catPhotos,
        builder: (context, photos, _) {
          final photo = photos[kind];
          return SizedBox(
            width: size,
            height: size * 1.1,
            child: photo == null
                ? CustomPaint(painter: CatPainter(kind, blink: blink))
                : _PhotoCat(kind: kind, path: photo, size: size),
          );
        },
      );
}

/// La foto del gatito en un círculo con orejitas y patitas.
class _PhotoCat extends StatelessWidget {
  const _PhotoCat({required this.kind, required this.path, required this.size});
  final CatKind kind;
  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = kind == CatKind.orange ? _orange : _gray;
    final d = size * 0.86;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Orejas
        Positioned(
          top: size * 0.04,
          child: SizedBox(
            width: d,
            height: d * 0.4,
            child: CustomPaint(painter: _EarsPainter(c.fur, c.outline)),
          ),
        ),
        Positioned(
          top: size * 0.14,
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.fur, width: size * 0.05),
              boxShadow: const [BoxShadow(blurRadius: 4, color: Color(0x33000000))],
            ),
            child: ClipOval(child: Image.file(File(path), fit: BoxFit.cover)),
          ),
        ),
        // Patitas
        for (final dx in [-0.18, 0.18])
          Positioned(
            bottom: size * 0.01,
            left: size / 2 + size * dx - size * 0.09,
            child: Container(
              width: size * 0.18,
              height: size * 0.11,
              decoration: BoxDecoration(
                color: kind == CatKind.gray ? Colors.white : c.fur,
                borderRadius: BorderRadius.circular(size),
                border: Border.all(color: c.outline, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _EarsPainter extends CustomPainter {
  const _EarsPainter(this.fur, this.outline);
  final Color fur;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    for (final flip in [false, true]) {
      double fx(double x) => flip ? w - x : x;
      final ear = Path()
        ..moveTo(fx(w * 0.08), h)
        ..quadraticBezierTo(fx(w * 0.05), h * 0.1, fx(w * 0.16), 0)
        ..quadraticBezierTo(fx(w * 0.3), h * 0.15, fx(w * 0.42), h * 0.75)
        ..close();
      canvas.drawPath(ear, Paint()..color = fur);
      canvas.drawPath(
          ear,
          Paint()
            ..color = outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      final inner = Path()
        ..moveTo(fx(w * 0.13), h * 0.9)
        ..quadraticBezierTo(fx(w * 0.12), h * 0.3, fx(w * 0.18), h * 0.22)
        ..quadraticBezierTo(fx(w * 0.27), h * 0.35, fx(w * 0.34), h * 0.8)
        ..close();
      canvas.drawPath(inner, Paint()..color = const Color(0xFFF7B9B9));
    }
  }

  @override
  bool shouldRepaint(_EarsPainter old) => old.fur != fur;
}

/// Gatito que respira y parpadea solo.
class AnimatedCatMascot extends StatefulWidget {
  const AnimatedCatMascot(
      {super.key, this.kind = CatKind.orange, this.size = 120, this.onTap, this.onLongPress});
  final CatKind kind;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

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
      onLongPress: widget.onLongPress,
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
