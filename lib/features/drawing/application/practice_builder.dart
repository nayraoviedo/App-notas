import 'dart:ui';

import '../domain/drawing.dart';
import '../domain/practice.dart';

/// Reparte los caracteres en las páginas necesarias (una fila por carácter).
/// Sin caracteres, crea una página con la cuadrícula vacía.
List<Drawing> buildPracticePages(PracticeSheet sheet, {int background = 0xFFFFFFFF}) {
  final layout = PracticeLayout(
    const Size(Drawing.a4Width, Drawing.a4Height),
    cellSize: sheet.cellSize,
    header: sheet.showPinyin ? sheet.cellSize * 0.42 : sheet.cellSize * 0.15,
  );
  final perPage = layout.rows;
  final chunks = <List<PracticeChar>>[
    for (var i = 0; i < sheet.chars.length; i += perPage)
      sheet.chars.sublist(i, (i + perPage).clamp(0, sheet.chars.length)),
  ];
  if (chunks.isEmpty) chunks.add(const []);

  return [
    for (final chunk in chunks)
      Drawing(
        width: Drawing.a4Width,
        height: Drawing.a4Height,
        paper: PaperStyle(
          template: PaperTemplate.blank,
          background: background,
          practice: sheet.copyWith(chars: chunk),
        ),
        layers: const [DrawingLayer(id: 'l1', name: 'Mi práctica')],
      ),
  ];
}
