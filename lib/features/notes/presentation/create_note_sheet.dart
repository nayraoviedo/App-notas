import 'package:flutter/material.dart';

import '../../drawing/domain/drawing.dart';
import '../../drawing/presentation/painters/paper_painter.dart';

/// Lo que se eligió al crear una nota.
class NewNoteOptions {
  const NewNoteOptions({
    required this.title,
    required this.withSheet,
    required this.paper,
    required this.landscape,
  });

  final String title;

  /// true: cuaderno de hojas para escribir a mano (se abre directo la hoja).
  /// false: nota libre (texto, audio, fotos…).
  final bool withSheet;
  final PaperStyle paper;
  final bool landscape;

  Drawing firstPage() => Drawing(
        width: landscape ? Drawing.a4Height : Drawing.a4Width,
        height: landscape ? Drawing.a4Width : Drawing.a4Height,
        paper: paper,
        layers: const [DrawingLayer(id: 'l1', name: 'Capa 1')],
      );
}

/// "Crear nota" al estilo StarNote: título, tipo y la hoja (plantilla,
/// color, separación y orientación).
Future<NewNoteOptions?> showCreateNoteSheet(BuildContext context) {
  return showModalBottomSheet<NewNoteOptions>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: const _CreateNoteForm(),
      ),
    ),
  );
}

/// Grupos de plantillas, como las pestañas de StarNote.
const _groups = <(String, List<PaperTemplate>)>[
  ('Básicas', [PaperTemplate.blank, PaperTemplate.lined, PaperTemplate.grid, PaperTemplate.dots]),
  ('Estudio', [PaperTemplate.cornell, PaperTemplate.todo]),
  ('Caligrafía china', [PaperTemplate.tianzi, PaperTemplate.mizi, PaperTemplate.jiugong]),
  ('Especiales', [PaperTemplate.music]),
];

class _CreateNoteForm extends StatefulWidget {
  const _CreateNoteForm();

  @override
  State<_CreateNoteForm> createState() => _CreateNoteFormState();
}

class _CreateNoteFormState extends State<_CreateNoteForm> {
  final _title = TextEditingController();
  bool _withSheet = true;
  PaperStyle _paper = const PaperStyle(template: PaperTemplate.lined);
  bool _landscape = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pageW = _landscape ? Drawing.a4Height : Drawing.a4Width;
    final pageH = _landscape ? Drawing.a4Width : Drawing.a4Height;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                Expanded(
                  child: Text('Crear nota', textAlign: TextAlign.center, style: text.titleMedium),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    NewNoteOptions(
                      title: _title.text.trim(),
                      withSheet: _withSheet,
                      paper: _paper,
                      landscape: _landscape,
                    ),
                  ),
                  child: const Text('Crear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Título de la nota',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: true, icon: Icon(Icons.draw_outlined), label: Text('Cuaderno de hojas')),
                    ButtonSegment(
                        value: false, icon: Icon(Icons.notes), label: Text('Nota libre')),
                  ],
                  selected: {_withSheet},
                  onSelectionChanged: (s) => setState(() => _withSheet = s.first),
                ),
                const SizedBox(height: 4),
                Text(
                  _withSheet
                      ? 'Hojas para escribir a mano, dibujar, poner textos y fotos.'
                      : 'Bloques de texto, grabaciones, fotos y videos (puedes agregar hojas después).',
                  style: text.bodySmall,
                ),
                if (_withSheet) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // Vista previa grande de la hoja elegida.
                      SizedBox(
                        width: 110,
                        height: (110 * pageH / pageW).clamp(60.0, 160.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: scheme.primary, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: pageW,
                                height: pageH,
                                child: PaperView(paper: _paper),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Color'),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final c in Paper.backgrounds)
                                  GestureDetector(
                                    onTap: () => setState(() => _paper = _paper.copyWith(background: c)),
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: Color(c),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          width: c == _paper.background ? 3 : 1,
                                          color: c == _paper.background ? scheme.primary : Colors.black26,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text('Separación'),
                            Slider(
                              min: 24,
                              max: 80,
                              value: _paper.spacing.clamp(24.0, 80.0),
                              onChanged: (v) => setState(() => _paper = _paper.copyWith(spacing: v)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.crop_portrait), label: Text('Vertical')),
                      ButtonSegment(value: true, icon: Icon(Icons.crop_landscape), label: Text('Horizontal')),
                    ],
                    selected: {_landscape},
                    onSelectionChanged: (s) => setState(() => _landscape = s.first),
                  ),
                  for (final (name, templates) in _groups) ...[
                    const SizedBox(height: 16),
                    Text(name, style: text.titleSmall),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 150,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: templates.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final t = templates[i];
                          final selected = t == _paper.template;
                          return GestureDetector(
                            onTap: () => setState(() => _paper = _paper.copyWith(template: t)),
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
                                  child: FittedBox(
                                    child: SizedBox(
                                      width: Drawing.a4Width,
                                      height: Drawing.a4Height,
                                      child: PaperView(paper: _paper.copyWith(template: t)),
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
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Para practicar caracteres chinos con modelos para calcar, usa '
                    '"Hoja → Práctica de caligrafía china" dentro de la nota.',
                    style: text.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
