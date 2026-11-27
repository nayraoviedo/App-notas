import 'package:flutter/material.dart';

import '../../application/drawing_controller.dart';
import '../../domain/drawing.dart';
import '../painters/paper_painter.dart';
import 'practice_sheet_dialog.dart';

/// Elegir tipo de hoja, color, separación de renglones y orientación.
class PaperSheet extends StatelessWidget {
  const PaperSheet({super.key, required this.controller, required this.onPickImage});
  final DrawingController controller;

  /// Elige una imagen de la galería y devuelve su ruta ya copiada a la app.
  final Future<String?> Function() onPickImage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final paper = controller.drawing.paper;
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hoja', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _templates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final t = _templates[i];
                      final selected = t == paper.template;
                      return GestureDetector(
                        onTap: () => controller.setPaper(paper.copyWith(template: t)),
                        child: Column(
                          children: [
                            Container(
                              width: 80,
                              height: 113,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  width: selected ? 2.5 : 1,
                                  color: selected ? scheme.primary : Colors.black26,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              // Vista previa: se dibuja la hoja real a escala.
                              child: FittedBox(
                                child: SizedBox(
                                  width: Drawing.a4Width,
                                  height: Drawing.a4Height,
                                  child: PaperView(paper: paper.copyWith(template: t)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(t.label, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: Text(paper.imagePath == null ? 'Subir mi hoja' : 'Cambiar imagen'),
                      onPressed: () async {
                        final path = await onPickImage();
                        if (path != null) {
                          controller.setPaper(
                              paper.copyWith(imagePath: path, template: PaperTemplate.blank));
                        }
                      },
                    ),
                    if (paper.imagePath != null)
                      TextButton(
                        onPressed: () => controller.setPaper(paper.copyWith(clearImage: true)),
                        child: const Text('Quitar imagen'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Text('田', style: TextStyle(fontSize: 18)),
                      label: Text(paper.practice == null
                          ? 'Práctica de caligrafía china'
                          : 'Editar práctica'),
                      onPressed: () async {
                        final r = await showPracticeSheetDialog(context, initial: paper.practice);
                        if (r != null) controller.setPaper(paper.copyWith(practice: r));
                      },
                    ),
                    if (paper.practice != null)
                      TextButton(
                        onPressed: () =>
                            controller.setPaper(paper.copyWith(clearPractice: true)),
                        child: const Text('Quitar práctica'),
                      ),
                  ],
                ),
                if (paper.practice != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'En esta página caben las filas que se ven; para muchos '
                      'caracteres crea la práctica desde la nota (botón Hoja) y se '
                      'reparten en varias páginas.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text('Color'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final c in Paper.backgrounds)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () => controller.setPaper(paper.copyWith(background: c)),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: c == paper.background ? 3 : 1,
                                color: c == paper.background ? scheme.primary : Colors.black26,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Separación'),
                    Expanded(
                      child: Slider(
                        min: 24,
                        max: 80,
                        value: paper.spacing.clamp(24, 80),
                        onChanged: (v) =>
                            controller.setPaper(paper.copyWith(spacing: v), undoable: false),
                      ),
                    ),
                  ],
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'v', icon: Icon(Icons.crop_portrait), label: Text('Vertical')),
                    ButtonSegment(value: 'h', icon: Icon(Icons.crop_landscape), label: Text('Horizontal')),
                    ButtonSegment(value: 'inf', icon: Icon(Icons.all_inclusive), label: Text('Infinito')),
                  ],
                  selected: {
                    controller.drawing.infinite
                        ? 'inf'
                        : controller.drawing.isLandscape
                            ? 'h'
                            : 'v'
                  },
                  onSelectionChanged: (s) {
                    final v = s.first;
                    if (v == 'inf') {
                      controller.setInfinite(true);
                      return;
                    }
                    controller.setInfinite(false);
                    controller.setLandscape(v == 'h');
                  },
                ),
                if (controller.drawing.infinite) ...[
                  const SizedBox(height: 10),
                  const Text('¿Hacia dónde crece?'),
                  const SizedBox(height: 6),
                  SegmentedButton<InfiniteGrow>(
                    segments: const [
                      ButtonSegment(
                          value: InfiniteGrow.down, icon: Icon(Icons.south), label: Text('Vertical')),
                      ButtonSegment(
                          value: InfiniteGrow.right, icon: Icon(Icons.east), label: Text('Horizontal')),
                      ButtonSegment(
                          value: InfiniteGrow.both, icon: Icon(Icons.open_with), label: Text('Libre')),
                    ],
                    selected: {controller.drawing.grow},
                    onSelectionChanged: (s) => controller.setInfinite(true, grow: s.first),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'La hoja crece sola cuando dibujas cerca del borde. Vertical: como un rollo '
                      'hacia abajo. Horizontal: hacia el lado, como una línea de tiempo. Libre: '
                      'para los dos lados (mapas mentales). Arriba eliges el tipo de papel.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

final _templates = [
  for (final (_, list) in Paper.groups) ...list,
  PaperTemplate.cover,
];
