import 'dart:io';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/fonts.dart';
import '../../domain/drawing.dart';
import '../../domain/practice.dart';

/// Dibuja el fondo de la hoja según la plantilla.
class PaperPainter extends CustomPainter {
  const PaperPainter(this.paper, {this.fontsGeneration = 0});
  final PaperStyle paper;

  /// Cambia cuando terminan de cargar las fuentes (para volver a pintar).
  final int fontsGeneration;

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

    final practice = paper.practice;
    if (practice != null) {
      _paintPractice(canvas, size, practice);
      return;
    }

    switch (paper.template) {
      case PaperTemplate.blank:
        break;

      case PaperTemplate.tianzi:
      case PaperTemplate.mizi:
      case PaperTemplate.jiugong:
        final grid = switch (paper.template) {
          PaperTemplate.mizi => PracticeGrid.mizi,
          PaperTemplate.jiugong => PracticeGrid.jiugong,
          _ => PracticeGrid.tianzi,
        };
        final layout = PracticeLayout(size, cellSize: s * 2, header: s * 0.6);
        for (var r = 0; r < layout.rows; r++) {
          for (var c = 0; c < layout.cols; c++) {
            _cell(canvas, layout.cellRect(r, c), grid);
          }
        }

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

  // --------------------------------------------------------- Caligrafía china

  Color get _ink => paper.isDark ? Colors.white : const Color(0xFF1F2328);

  void _cell(Canvas canvas, Rect r, PracticeGrid grid) {
    final border = Paper.accentColor(paper);
    canvas.drawRect(
      r,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    final guide = Paint()
      ..color = border.withValues(alpha: border.a * 0.6)
      ..strokeWidth = 1;
    switch (grid) {
      case PracticeGrid.tianzi:
        _dashed(canvas, r.topCenter, r.bottomCenter, guide);
        _dashed(canvas, r.centerLeft, r.centerRight, guide);
      case PracticeGrid.mizi:
        _dashed(canvas, r.topCenter, r.bottomCenter, guide);
        _dashed(canvas, r.centerLeft, r.centerRight, guide);
        _dashed(canvas, r.topLeft, r.bottomRight, guide);
        _dashed(canvas, r.topRight, r.bottomLeft, guide);
      case PracticeGrid.jiugong:
        for (final t in [1 / 3, 2 / 3]) {
          _dashed(canvas, Offset(r.left + r.width * t, r.top),
              Offset(r.left + r.width * t, r.bottom), guide);
          _dashed(canvas, Offset(r.left, r.top + r.height * t),
              Offset(r.right, r.top + r.height * t), guide);
        }
      case PracticeGrid.plain:
        break;
    }
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint p,
      {double dash = 5, double gap = 4}) {
    final total = (b - a).distance;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), p);
    }
  }

  void _paintPractice(Canvas canvas, Size size, PracticeSheet p) {
    final layout = PracticeLayout(
      size,
      cellSize: p.cellSize,
      header: p.showPinyin ? p.cellSize * 0.42 : p.cellSize * 0.15,
    );
    final charStyle = fontStyle(p.font, size: p.cellSize * 0.76).copyWith(height: 1);

    for (var r = 0; r < layout.rows; r++) {
      final ch = r < p.chars.length ? p.chars[r] : null;

      // Pinyin y significado encima de la fila.
      if (ch != null && p.showPinyin && (ch.pinyin != null || ch.meaning != null)) {
        final label = [ch.pinyin, ch.meaning].whereType<String>().join(' · ');
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontSize: p.cellSize * 0.24,
              color: _ink.withValues(alpha: 0.6),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width - layout.left * 2);
        final rowTop = layout.cellRect(r, 0).top;
        tp.paint(canvas, Offset(layout.left, rowTop - tp.height - 4));
      }

      for (var c = 0; c < layout.cols; c++) {
        final rect = layout.cellRect(r, c);
        _cell(canvas, rect, p.grid);
        if (ch == null) continue;
        // Celda 1: modelo. Las siguientes: copias tenues para calcar.
        final double alpha;
        if (c == 0) {
          alpha = 0.9;
        } else if (c <= p.traceCount) {
          alpha = 0.16;
        } else {
          continue;
        }
        final tp = TextPainter(
          text: TextSpan(text: ch.char, style: charStyle.copyWith(color: _ink.withValues(alpha: alpha))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.fontsGeneration != fontsGeneration ||
      !identical(old.paper.practice, paper.practice) ||
      old.paper.template != paper.template ||
      old.paper.background != paper.background ||
      old.paper.spacing != paper.spacing ||
      old.paper.imagePath != paper.imagePath;
}

/// Fondo completo de la hoja: imagen personalizada (si hay) + plantilla.
/// En hojas de práctica espera a que cargue la fuente china para repintar.
class PaperView extends StatefulWidget {
  const PaperView({super.key, required this.paper});
  final PaperStyle paper;

  @override
  State<PaperView> createState() => _PaperViewState();
}

class _PaperViewState extends State<PaperView> {
  int _fontsGeneration = 0;

  @override
  void initState() {
    super.initState();
    _waitForFont();
  }

  @override
  void didUpdateWidget(PaperView old) {
    super.didUpdateWidget(old);
    if (old.paper.practice?.font != widget.paper.practice?.font) _waitForFont();
  }

  Future<void> _waitForFont() async {
    final font = widget.paper.practice?.font;
    if (font == null) return;
    fontStyle(font); // inicia la descarga si hace falta
    try {
      await GoogleFonts.pendingFonts();
    } catch (_) {
      return; // sin internet: se ve con la fuente del sistema
    }
    if (mounted) setState(() => _fontsGeneration++);
  }

  @override
  Widget build(BuildContext context) {
    final paper = widget.paper;
    final painter = CustomPaint(
      painter: PaperPainter(paper, fontsGeneration: _fontsGeneration),
    );
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

