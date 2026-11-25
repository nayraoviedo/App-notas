import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/drawing.dart';

/// Dibuja el fondo de la hoja según la plantilla.
class PaperPainter extends CustomPainter {
  const PaperPainter(this.paper);
  final PaperStyle paper;

  @override
  void paint(Canvas canvas, Size size) {
    // Con hoja personalizada, el fondo es la imagen (ver [PaperView]).
    if (paper.imagePath == null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Color(paper.background));
    }

    final line = Paper.lineColor(paper);
    final thin = Paint()
      ..color = line
      ..strokeWidth = 1.2;
    final strong = Paint()
      ..color = Paper.accentColor(paper)
      ..strokeWidth = 2;
    final s = paper.spacing;
    final top = s * 2.5;

    void hLines({double left = 0}) {
      for (var y = top; y < size.height - s * 0.5; y += s) {
        canvas.drawLine(Offset(left, y), Offset(size.width, y), thin);
      }
    }

    switch (paper.template) {
      case PaperTemplate.blank:
        break;

      case PaperTemplate.lined:
        hLines();
        canvas.drawLine(Offset(s * 2, 0), Offset(s * 2, size.height), strong);

      case PaperTemplate.grid:
        for (var y = 0.0; y < size.height; y += s) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), thin);
        }
        for (var x = 0.0; x < size.width; x += s) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), thin);
        }

      case PaperTemplate.dots:
        final dot = Paint()..color = line.withValues(alpha: (line.a * 1.6).clamp(0, 1));
        for (var y = s; y < size.height; y += s) {
          for (var x = s; x < size.width; x += s) {
            canvas.drawCircle(Offset(x, y), 2, dot);
          }
        }

      case PaperTemplate.cornell:
        // Columna de palabras clave, área de notas y resumen abajo.
        final summaryTop = size.height * 0.8;
        for (var y = top; y < summaryTop; y += s) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), thin);
        }
        canvas.drawLine(Offset(size.width * 0.28, top - s), Offset(size.width * 0.28, summaryTop), strong);
        canvas.drawLine(Offset(0, summaryTop), Offset(size.width, summaryTop), strong);
        canvas.drawLine(Offset(0, top - s), Offset(size.width, top - s), strong);

      case PaperTemplate.todo:
        hLines();
        final box = Paint()
          ..color = Paper.accentColor(paper)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        final b = s * 0.5;
        for (var y = top; y < size.height - s * 0.5; y += s) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(s * 0.6, y - b - s * 0.18, b, b), const Radius.circular(4)),
            box,
          );
        }

      case PaperTemplate.music:
        // Pentagramas de 5 líneas.
        final gap = s * 0.35;
        final staffHeight = gap * 4;
        final margin = s * 1.2;
        for (var y = top; y + staffHeight < size.height - s; y += staffHeight + s * 1.6) {
          for (var i = 0; i < 5; i++) {
            final ly = y + i * gap;
            canvas.drawLine(Offset(margin, ly), Offset(size.width - margin, ly), thin);
          }
        }
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.paper.template != paper.template ||
      old.paper.background != paper.background ||
      old.paper.spacing != paper.spacing ||
      old.paper.imagePath != paper.imagePath;
}

/// Fondo completo de la hoja: imagen personalizada (si hay) + plantilla.
class PaperView extends StatelessWidget {
  const PaperView({super.key, required this.paper});
  final PaperStyle paper;

  @override
  Widget build(BuildContext context) {
    final painter = CustomPaint(painter: PaperPainter(paper));
    if (paper.imagePath == null) return painter;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Color(paper.background)),
        Image.file(File(paper.imagePath!), fit: BoxFit.fill),
        painter,
      ],
    );
  }
}

class Paper {
  /// Colores de hoja disponibles (blanco, crema, verde, gris, oscuro).
  static const backgrounds = [0xFFFFFFFF, 0xFFFFF8E7, 0xFFEAF4EC, 0xFFE9EBF0, 0xFF2B2B2E];

  static Color lineColor(PaperStyle p) => p.isDark
      ? Colors.white.withValues(alpha: 0.14)
      : const Color(0xFF5B7DB1).withValues(alpha: 0.28);

  static Color accentColor(PaperStyle p) => p.isDark
      ? Colors.white.withValues(alpha: 0.3)
      : const Color(0xFFE06C75).withValues(alpha: 0.55);
}
