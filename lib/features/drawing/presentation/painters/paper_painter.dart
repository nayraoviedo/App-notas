import 'dart:io';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/fonts.dart';
import '../../domain/drawing.dart';
import '../../domain/practice.dart';
import '../../../notebooks/domain/notebook.dart' show CoverPattern;
import '../../../notebooks/presentation/cover_designs.dart';

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

    void hLines({double left = 0, double? step}) {
      final st = step ?? s;
      for (var y = top; y < size.height - st * 0.5; y += st) {
        canvas.drawLine(Offset(left, y), Offset(size.width, y), thin);
      }
    }

    void gridLines(double step, Paint p) {
      for (var y = 0.0; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      }
      for (var x = 0.0; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
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
        _staves(canvas, size, lines: 5, thin: thin);

      case PaperTemplate.guitarTab:
        _staves(canvas, size, lines: 6, thin: thin, label: 'TAB');

      case PaperTemplate.linedNarrow:
        hLines(step: s * 0.75);
      case PaperTemplate.linedWide:
        hLines(step: s * 1.4);

      case PaperTemplate.miniGrid:
        gridLines(s * 0.5, Paint()
          ..color = line.withValues(alpha: line.a * 0.7)
          ..strokeWidth = 0.8);

      case PaperTemplate.cornellB:
        final summaryTop = size.height * 0.82;
        final col = size.width * 0.22;
        for (var y = top; y < summaryTop; y += s * 0.75) {
          canvas.drawLine(Offset(col, y), Offset(size.width, y), thin);
        }
        canvas.drawLine(Offset(col, top - s), Offset(col, summaryTop), strong);
        canvas.drawLine(Offset(0, summaryTop), Offset(size.width, summaryTop), strong);
        canvas.drawLine(Offset(0, top - s), Offset(size.width, top - s), strong);

      case PaperTemplate.cornellC:
        canvas.drawLine(Offset(size.width * 0.18, top - s), Offset(size.width * 0.18, size.height), strong);
        canvas.drawLine(Offset(0, top - s), Offset(size.width, top - s), strong);

      case PaperTemplate.ebbinghaus:
        _ebbinghaus(canvas, size, thin, strong);

      case PaperTemplate.dailyPlan:
        _dailyPlan(canvas, size, thin, strong);

      case PaperTemplate.weeklyPlan:
        _weeklyPlan(canvas, size, thin, strong);

      case PaperTemplate.habits:
        _habits(canvas, size, thin, strong);

      case PaperTemplate.reading:
        _label(canvas, 'Libro:', Offset(s, s * 0.9), s * 0.45);
        _label(canvas, 'Autor:', Offset(size.width * 0.55, s * 0.9), s * 0.45);
        canvas.drawLine(Offset(s, s * 1.8), Offset(size.width - s, s * 1.8), strong);
        _label(canvas, 'Ideas principales', Offset(s, s * 2.2), s * 0.4);
        for (var y = s * 3.4; y < size.height * 0.62; y += s) {
          canvas.drawLine(Offset(s, y), Offset(size.width - s, y), thin);
        }
        final q = size.height * 0.64;
        canvas.drawLine(Offset(s, q), Offset(size.width - s, q), strong);
        _label(canvas, 'Citas favoritas', Offset(s, q + s * 0.3), s * 0.4);
        for (var y = q + s * 1.5; y < size.height - s; y += s) {
          canvas.drawLine(Offset(s, y), Offset(size.width - s, y), thin);
        }

      case PaperTemplate.englishLines:
        // Grupos de 4 renglones (caligrafía en inglés): el del medio punteado
        // y la línea base en color.
        final g = s * 0.45;
        final base = Paint()
          ..color = Paper.accentColor(paper)
          ..strokeWidth = 1.4;
        for (var y = top; y + g * 3 < size.height - s; y += g * 3 + s * 0.9) {
          canvas.drawLine(Offset(s, y), Offset(size.width - s, y), thin);
          _dashed(canvas, Offset(s, y + g), Offset(size.width - s, y + g), thin);
          canvas.drawLine(Offset(s, y + g * 2), Offset(size.width - s, y + g * 2), base);
          canvas.drawLine(Offset(s, y + g * 3), Offset(size.width - s, y + g * 3), thin);
        }

      case PaperTemplate.soccer:
        _soccer(canvas, size);

      case PaperTemplate.basketball:
        _basketball(canvas, size);

      case PaperTemplate.cover:
        _cover(canvas, size);
    }
  }

  // ------------------------------------------------------------ Ayudantes

  void _label(Canvas canvas, String text, Offset at, double fontSize,
      {double maxWidth = 1000, TextAlign align = TextAlign.left, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: _ink.withValues(alpha: 0.5),
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final dx = switch (align) {
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy));
  }

  /// Pentagramas / tablaturas.
  void _staves(Canvas canvas, Size size, {required int lines, required Paint thin, String? label}) {
    final s = paper.spacing;
    final gap = s * 0.35;
    final staffHeight = gap * (lines - 1);
    final margin = s * 1.2;
    for (var y = s * 2.5; y + staffHeight < size.height - s; y += staffHeight + s * 1.6) {
      for (var i = 0; i < lines; i++) {
        final ly = y + i * gap;
        canvas.drawLine(Offset(margin, ly), Offset(size.width - margin, ly), thin);
      }
      canvas.drawLine(Offset(margin, y), Offset(margin, y + staffHeight), thin);
      canvas.drawLine(
          Offset(size.width - margin, y), Offset(size.width - margin, y + staffHeight), thin);
      if (label != null) {
        _label(canvas, label, Offset(margin + 6, y + staffHeight / 2 - gap), gap * 1.6, bold: true);
      }
    }
  }

  void _ebbinghaus(Canvas canvas, Size size, Paint thin, Paint strong) {
    final s = paper.spacing;
    final left = s * 0.8, right = size.width - s * 0.8;
    final top = s * 1.6;
    const reviews = ['1', '2', '4', '7', '15', '30'];
    final reviewW = (right - left) * 0.06;
    final cols = <double>[
      left,
      left + (right - left) * 0.07, // Nº
      left + (right - left) * 0.2, // Fecha
      right - reviewW * reviews.length, // Contenido
      for (var i = 1; i <= reviews.length; i++) right - reviewW * (reviews.length - i),
    ];
    _label(canvas, 'Curva del olvido: repasa en los días marcados', Offset(left, s * 0.5), s * 0.42);
    final rowH = s * 0.9;
    final bottom = size.height - s;
    canvas.drawRect(
      Rect.fromLTRB(left, top, right, bottom),
      Paint()
        ..color = strong.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final x in cols.skip(1).take(cols.length - 2)) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), thin);
    }
    final headers = ['Nº', 'Fecha', 'Contenido', ...reviews];
    for (var i = 0; i < headers.length; i++) {
      final cx = (cols[i] + cols[i + 1]) / 2;
      _label(canvas, headers[i], Offset(cx, top + rowH * 0.22), s * 0.34, align: TextAlign.center);
    }
    for (var y = top + rowH; y < bottom; y += rowH) {
      canvas.drawLine(Offset(left, y), Offset(right, y), y == top + rowH ? strong : thin);
    }
  }

  void _dailyPlan(Canvas canvas, Size size, Paint thin, Paint strong) {
    final s = paper.spacing;
    final m = s * 0.8;
    _label(canvas, 'Fecha:', Offset(m, s * 0.6), s * 0.45);
    for (var i = 0; i < 7; i++) {
      canvas.drawCircle(Offset(size.width - m - i * s * 0.75, s * 0.9), s * 0.22,
          Paint()
            ..color = Paper.accentColor(paper)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    final top = s * 1.8;
    final mid = size.width * 0.5;
    final notesTop = size.height * 0.78;
    final box = Paint()
      ..color = strong.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawRRect(RRect.fromLTRBR(m, top, mid - m / 2, notesTop - m / 2, const Radius.circular(10)), box);
    canvas.drawRRect(
        RRect.fromLTRBR(mid + m / 2, top, size.width - m, notesTop - m / 2, const Radius.circular(10)), box);
    canvas.drawRRect(
        RRect.fromLTRBR(m, notesTop, size.width - m, size.height - m, const Radius.circular(10)), box);
    _label(canvas, 'Horario', Offset(m + 12, top + 8), s * 0.4, bold: true);
    _label(canvas, 'Pendientes', Offset(mid + m / 2 + 12, top + 8), s * 0.4, bold: true);
    _label(canvas, 'Notas', Offset(m + 12, notesTop + 8), s * 0.4, bold: true);
    final rowsTop = top + s * 1.1;
    final rowH = (notesTop - m - rowsTop) / 17;
    for (var i = 0; i < 17; i++) {
      final y = rowsTop + i * rowH;
      canvas.drawLine(Offset(m + 8, y), Offset(mid - m / 2 - 8, y), thin);
      _label(canvas, '${6 + i}', Offset(m + 12, y + rowH * 0.2), rowH * 0.45);
      canvas.drawLine(Offset(mid + m / 2 + 8, y), Offset(size.width - m - 8, y), thin);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(mid + m / 2 + 14, y + rowH * 0.25, rowH * 0.5, rowH * 0.5),
              const Radius.circular(3)),
          box);
    }
  }

  void _weeklyPlan(Canvas canvas, Size size, Paint thin, Paint strong) {
    final s = paper.spacing;
    final m = s * 0.8;
    const days = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo', 'Notas'];
    final top = s * 1.6;
    _label(canvas, 'Semana:', Offset(m, s * 0.5), s * 0.45);
    final w = (size.width - m * 3) / 2;
    final h = (size.height - top - m * 4) / 4;
    final box = Paint()
      ..color = strong.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (var i = 0; i < days.length; i++) {
      final col = i % 2, row = i ~/ 2;
      final r = Rect.fromLTWH(m + col * (w + m), top + row * (h + m), w, h);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), box);
      _label(canvas, days[i], r.topLeft + const Offset(12, 8), s * 0.4, bold: true);
      for (var y = r.top + s * 1.4; y < r.bottom - 8; y += s * 0.8) {
        canvas.drawLine(Offset(r.left + 10, y), Offset(r.right - 10, y), thin);
      }
    }
  }

  void _habits(Canvas canvas, Size size, Paint thin, Paint strong) {
    final s = paper.spacing;
    final m = s * 0.6;
    _label(canvas, 'Hábitos del mes:', Offset(m, s * 0.5), s * 0.45);
    final top = s * 1.6;
    final nameW = size.width * 0.24;
    final cell = (size.width - m * 2 - nameW) / 31;
    final rows = ((size.height - top - m) / (cell * 1.5)).floor();
    final rowH = cell * 1.5;
    for (var d = 0; d < 31; d++) {
      _label(canvas, '${d + 1}', Offset(m + nameW + cell * (d + 0.5), top + rowH * 0.2), cell * 0.5,
          align: TextAlign.center);
    }
    for (var r = 0; r <= rows; r++) {
      final y = top + rowH * (r + 1);
      canvas.drawLine(Offset(m, y), Offset(size.width - m, y), r == 0 ? strong : thin);
    }
    for (var d = 0; d <= 31; d++) {
      final x = m + nameW + cell * d;
      canvas.drawLine(Offset(x, top), Offset(x, top + rowH * (rows + 1)), d == 0 ? strong : thin);
    }
  }

  void _soccer(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Paper.lineColor(paper).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final m = paper.spacing;
    final f = Rect.fromLTRB(m, m, size.width - m, size.height - m);
    canvas.drawRect(f, p);
    canvas.drawLine(f.centerLeft, f.centerRight, p);
    canvas.drawCircle(f.center, f.width * 0.15, p);
    canvas.drawCircle(f.center, 4, Paint()..color = p.color);
    for (final top in [true, false]) {
      final bigW = f.width * 0.6, bigH = f.height * 0.13;
      final smallW = f.width * 0.3, smallH = f.height * 0.05;
      final y0 = top ? f.top : f.bottom;
      final dir = top ? 1.0 : -1.0;
      canvas.drawRect(Rect.fromPoints(Offset(f.center.dx - bigW / 2, y0), Offset(f.center.dx + bigW / 2, y0 + dir * bigH)), p);
      canvas.drawRect(Rect.fromPoints(Offset(f.center.dx - smallW / 2, y0), Offset(f.center.dx + smallW / 2, y0 + dir * smallH)), p);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(f.center.dx, y0 + dir * bigH * 0.72), radius: f.width * 0.15),
        top ? 0.65 : math.pi + 0.65,
        math.pi - 1.3,
        false,
        p,
      );
    }
  }

  void _basketball(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Paper.lineColor(paper).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final m = paper.spacing;
    final f = Rect.fromLTRB(m, m, size.width - m, size.height - m);
    canvas.drawRect(f, p);
    canvas.drawLine(f.centerLeft, f.centerRight, p);
    canvas.drawCircle(f.center, f.width * 0.13, p);
    for (final top in [true, false]) {
      final y0 = top ? f.top : f.bottom;
      final dir = top ? 1.0 : -1.0;
      final keyW = f.width * 0.32, keyH = f.height * 0.2;
      canvas.drawRect(Rect.fromPoints(Offset(f.center.dx - keyW / 2, y0), Offset(f.center.dx + keyW / 2, y0 + dir * keyH)), p);
      canvas.drawCircle(Offset(f.center.dx, y0 + dir * keyH), keyW / 2, p);
      final hoop = Offset(f.center.dx, y0 + dir * f.height * 0.05);
      canvas.drawCircle(hoop, 10, p);
      final r = f.width * 0.45;
      canvas.drawArc(Rect.fromCircle(center: hoop, radius: r), top ? 0.15 : math.pi + 0.15,
          math.pi - 0.3, false, p);
    }
  }

  /// Tapa de cuaderno: franjas de color, banda clara al centro con una
  /// estrellita y un elástico. Con [PaperStyle.design] u obra de arte, la
  /// tapa ilustrada con su placa central.
  void _cover(Canvas canvas, Size size) {
    final design = CoverPattern.values.where((p) => p.name == paper.design).firstOrNull;
    if (design != null || paper.imagePath != null) {
      if (design != null) paintIllustratedCover(canvas, size, design, Color(paper.background));
      paintPlateBox(canvas, size, design != null ? Color(paper.background) : const Color(0xFFB9C6B0));
      return;
    }
    final base = Color(paper.background);
    final hsl = HSLColor.fromColor(base);
    final dark = hsl.withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0)).toColor();
    final bandTop = size.height * 0.36, bandBottom = size.height * 0.56;
    canvas.drawRect(Rect.fromLTRB(0, bandTop, size.width, bandBottom), Paint()..color = Colors.white);
    final line = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = 1.5;
    final cy = (bandTop + bandBottom) / 2;
    final star = size.width * 0.04;
    canvas.drawLine(Offset(size.width * 0.06, cy), Offset(size.width / 2 - star * 2, cy), line);
    canvas.drawLine(Offset(size.width / 2 + star * 2, cy), Offset(size.width * 0.94, cy), line);
    canvas.drawPath(_sparkle(Offset(size.width / 2, cy), star),
        Paint()..color = Colors.black.withValues(alpha: 0.4));
    // Elástico.
    final strap = Rect.fromLTWH(size.width * 0.8, 0, size.width * 0.05, size.height);
    canvas.drawRect(Rect.fromLTRB(strap.left, 0, strap.right, bandTop), Paint()..color = dark);
    canvas.drawRect(Rect.fromLTRB(strap.left, bandBottom, strap.right, size.height), Paint()..color = dark);
  }

  static Path _sparkle(Offset c, double r) {
    final p = Path()..moveTo(c.dx, c.dy - r);
    p.quadraticBezierTo(c.dx + r * 0.12, c.dy - r * 0.12, c.dx + r, c.dy);
    p.quadraticBezierTo(c.dx + r * 0.12, c.dy + r * 0.12, c.dx, c.dy + r);
    p.quadraticBezierTo(c.dx - r * 0.12, c.dy + r * 0.12, c.dx - r, c.dy);
    p.quadraticBezierTo(c.dx - r * 0.12, c.dy - r * 0.12, c.dx, c.dy - r);
    return p..close();
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
      old.paper.imagePath != paper.imagePath ||
      old.paper.design != paper.design;
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
    final img = paper.imagePath;
    if (img == null) return painter;
    // Las obras de arte de las tapas vienen dentro de la app (assets/).
    final isAsset = img.startsWith('assets/');
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Color(paper.background)),
        if (isAsset)
          Image.asset(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())
        else
          Image.file(File(img), fit: BoxFit.fill),
        painter,
      ],
    );
  }
}

class Paper {
  /// Colores de hoja disponibles (blanco, crema, verde, gris, oscuro).
  static const backgrounds = [0xFFFFFFFF, 0xFFEAF4EC, 0xFFFFF8E7, 0xFFE9EBF0, 0xFF2B2B2E];

  /// Plantillas agrupadas como en StarNote (Base, Estudio, Plan…).
  static const groups = <(String, List<PaperTemplate>)>[
    ('Base', [
      PaperTemplate.blank,
      PaperTemplate.linedNarrow,
      PaperTemplate.lined,
      PaperTemplate.linedWide,
      PaperTemplate.miniGrid,
      PaperTemplate.grid,
      PaperTemplate.dots,
    ]),
    ('Estudio', [
      PaperTemplate.cornell,
      PaperTemplate.cornellB,
      PaperTemplate.cornellC,
      PaperTemplate.ebbinghaus,
      PaperTemplate.todo,
    ]),
    ('Plan', [PaperTemplate.dailyPlan, PaperTemplate.weeklyPlan, PaperTemplate.habits]),
    ('Vida', [PaperTemplate.reading]),
    ('Escribir', [
      PaperTemplate.englishLines,
      PaperTemplate.tianzi,
      PaperTemplate.mizi,
      PaperTemplate.jiugong,
    ]),
    ('Especialidad', [
      PaperTemplate.music,
      PaperTemplate.guitarTab,
      PaperTemplate.soccer,
      PaperTemplate.basketball,
    ]),
  ];

  /// Colores de tapa.
  static const coverColors = [
    0xFFC5CDD6, 0xFFF4C7D0, 0xFFBFE3D0, 0xFFD9CCF0, 0xFFF7E1B5, 0xFFB9D7EE, 0xFF8FA3B8, 0xFF2F3A4A,
  ];

  static Color lineColor(PaperStyle p) => p.isDark
      ? Colors.white.withValues(alpha: 0.14)
      : const Color(0xFF5B7DB1).withValues(alpha: 0.28);

  static Color accentColor(PaperStyle p) => p.isDark
      ? Colors.white.withValues(alpha: 0.3)
      : const Color(0xFFE06C75).withValues(alpha: 0.55);
}

