import 'package:flutter/material.dart';

import '../../drawing/domain/drawing.dart';
import '../../drawing/presentation/painters/paper_painter.dart';
import 'note_tags_dialog.dart';

/// Lo que se eligió al crear una nota.
class NewNoteOptions {
  const NewNoteOptions({
    required this.title,
    required this.withSheet,
    required this.paper,
    required this.landscape,
    this.withCover = true,
    this.coverColor = 0xFFC5CDD6,
    this.tags = const [],
  });

  final String title;

  /// true: cuaderno de hojas para escribir a mano (se abre directo la hoja).
  /// false: nota libre (texto, audio, fotos…).
  final bool withSheet;
  final PaperStyle paper;
  final bool landscape;

  /// Primera página como tapa del cuaderno.
  final bool withCover;
  final int coverColor;
  final List<String> tags;

  double get _w => landscape ? Drawing.a4Height : Drawing.a4Width;
  double get _h => landscape ? Drawing.a4Width : Drawing.a4Height;

  Drawing firstPage() => Drawing(
        width: _w,
        height: _h,
        paper: paper,
        layers: const [DrawingLayer(id: 'l1', name: 'Capa 1')],
      );

  /// La tapa: franjas de color, banda clara y el título escrito en ella.
  Drawing coverPage() => Drawing(
        width: _w,
        height: _h,
        paper: PaperStyle(template: PaperTemplate.cover, background: coverColor),
        layers: [
          DrawingLayer(
            id: 'l1',
            name: 'Capa 1',
            items: [
              if (title.trim().isNotEmpty)
                TextItem(
                  id: 'cover-title',
                  x: _w / 2,
                  y: _h * 0.41,
                  text: title.trim(),
                  font: 'Dancing Script',
                  size: 60,
                  color: 0xFF3A3F47,
                  align: TextItemAlign.center,
                  width: _w * 0.8,
                ),
            ],
          ),
        ],
      );

  /// Páginas iniciales del cuaderno.
  List<Drawing> pages() => [if (withCover) coverPage(), firstPage()];
}

/// "Crear nota" al estilo StarNote: tapa y papel, título, etiquetas, formato
/// y la plantilla con su color.
Future<NewNoteOptions?> showCreateNoteSheet(BuildContext context) {
  return showModalBottomSheet<NewNoteOptions>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFF3F4F6),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.92,
        child: const CreateNoteForm(),
      ),
    ),
  );
}

class CreateNoteForm extends StatefulWidget {
  const CreateNoteForm({super.key});

  @override
  State<CreateNoteForm> createState() => _CreateNoteFormState();
}

class _CreateNoteFormState extends State<CreateNoteForm> {
  final _title = TextEditingController();
  bool _withSheet = true;
  bool _withCover = true;
  bool _editingCover = false;
  int _coverColor = Paper.coverColors.first;
  PaperStyle _paper = const PaperStyle(template: PaperTemplate.blank);
  bool _landscape = false;
  List<String> _tags = const [];
  String _group = Paper.groups.first.$1;
  final _groupKeys = {for (final (g, _) in Paper.groups) g: GlobalKey()};

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  double get _pageW => _landscape ? Drawing.a4Height : Drawing.a4Width;
  double get _pageH => _landscape ? Drawing.a4Width : Drawing.a4Height;

  void _jumpTo(String group) {
    setState(() => _group = group);
    final ctx = _groupKeys[group]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
    }
  }

  Widget _page(PaperStyle paper, {double width = 62}) => SizedBox(
        width: width,
        height: width * _pageH / _pageW,
        child: FittedBox(
          child: SizedBox(width: _pageW, height: _pageH, child: PaperView(paper: paper)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = const Color(0xFF1E8CB4);

    Widget card({required Widget child, required String label, required bool selected, required VoidCallback onTap, bool dashed = false}) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 78,
            padding: const EdgeInsets.fromLTRB(7, 10, 7, 6),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? accent : (dashed ? Colors.black26 : Colors.transparent),
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(4), child: child),
                const SizedBox(height: 8),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: selected ? accent : null, fontSize: 13)),
              ],
            ),
          ),
        );

    Widget row(String label, Widget trailing, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [Expanded(child: Text(label)), trailing]),
          ),
        );

    return SafeArea(
      child: Column(
        children: [
          // Encabezado
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 12, 4),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancelar', style: TextStyle(color: accent)),
                ),
                Expanded(child: Text('Crear nota', textAlign: TextAlign.center, style: text.titleLarge)),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: () => Navigator.pop(
                    context,
                    NewNoteOptions(
                      title: _title.text.trim(),
                      withSheet: _withSheet,
                      paper: _paper,
                      landscape: _landscape,
                      withCover: _withSheet && _withCover,
                      coverColor: _coverColor,
                      tags: _tags,
                    ),
                  ),
                  child: const Text('Crear'),
                ),
              ],
            ),
          ),
          // Tapa · Papel · datos
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 560;
            final info = _info(accent, row);
            final covers = Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_withSheet) ...[
                  card(
                    label: 'Tapa',
                    selected: _editingCover,
                    dashed: true,
                    onTap: () => setState(() {
                      _editingCover = true;
                      _withCover = true;
                    }),
                    child: Opacity(
                      opacity: _withCover ? 1 : 0.35,
                      child: _page(PaperStyle(template: PaperTemplate.cover, background: _coverColor)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  card(
                    label: 'Papel',
                    selected: !_editingCover,
                    onTap: () => setState(() => _editingCover = false),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        boxShadow: [BoxShadow(blurRadius: 3, color: Colors.black12)],
                      ),
                      child: _page(_paper),
                    ),
                  ),
                ],
              ],
            );
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [covers, const SizedBox(width: 8), Expanded(child: info)],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_withSheet) ...[
                          // Tapa y papel uno sobre otro a la izquierda, chicos.
                          covers,
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: info),
                      ],
                    ),
            );
          }),
          if (!_withSheet)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nota libre: bloques de texto, grabaciones, fotos y videos. '
                  'Puedes agregar hojas para escribir a mano después.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
              ),
            )
          else
            Expanded(
              child: Container(
                color: Colors.white,
                child: _editingCover ? _coverPicker(accent) : _templatePicker(accent, scheme),
              ),
            ),
        ],
      ),
    );
  }

  Widget _info(Color accent, Widget Function(String, Widget, {VoidCallback? onTap}) row) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
                            children: [
                              TextField(
                                controller: _title,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Título de la nota',
                                  filled: true,
                                  fillColor: const Color(0xFFF3F4F6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              row(
                                'Etiqueta',
                                _tags.isEmpty
                                    ? const Icon(Icons.add_circle_outline, color: Colors.black54)
                                    : Flexible(
                                        child: Text(_tags.map((t) => '#$t').join(' '),
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: accent)),
                                      ),
                                onTap: () async {
                                  final r = await showTagPicker(context, initial: _tags);
                                  if (r != null) setState(() => _tags = r);
                                },
                              ),
                              if (_withSheet)
                                row(
                                  'Tapa',
                                  Switch(
                                    value: _withCover,
                                    onChanged: (v) => setState(() {
                                      _withCover = v;
                                      if (!v) _editingCover = false;
                                    }),
                                  ),
                                ),
                              row(
                                'Formato',
                                DropdownButton<bool>(
                                  value: _landscape,
                                  underline: const SizedBox.shrink(),
                                  isDense: true,
                                  items: const [
                                    DropdownMenuItem(value: false, child: Text('Vertical')),
                                    DropdownMenuItem(value: true, child: Text('Horizontal')),
                                  ],
                                  onChanged: (v) => setState(() => _landscape = v ?? false),
                                ),
                              ),
                              row(
                                'Tipo',
                                DropdownButton<bool>(
                                  value: _withSheet,
                                  underline: const SizedBox.shrink(),
                                  isDense: true,
                                  items: const [
                                    DropdownMenuItem(value: true, child: Text('Cuaderno')),
                                    DropdownMenuItem(value: false, child: Text('Nota libre')),
                                  ],
                                  onChanged: (v) => setState(() => _withSheet = v ?? true),
                                ),
                              ),
                            ],
        ),
      );

  Widget _coverPicker(Color accent) => GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 110,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.7,
        ),
        itemCount: Paper.coverColors.length,
        itemBuilder: (context, i) {
          final c = Paper.coverColors[i];
          final selected = c == _coverColor;
          return GestureDetector(
            onTap: () => setState(() => _coverColor = c),
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: selected ? accent : Colors.black12, width: selected ? 2.5 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _pageW,
                      height: _pageH,
                      child: PaperView(paper: PaperStyle(template: PaperTemplate.cover, background: c)),
                    ),
                  ),
                ),
                if (selected) _check(accent),
              ],
            ),
          );
        },
      );

  Widget _check(Color accent) => Positioned(
        bottom: 8,
        left: 0,
        right: 0,
        child: Center(
          child: CircleAvatar(
            radius: 12,
            backgroundColor: accent,
            child: const Icon(Icons.check, size: 16, color: Colors.white),
          ),
        ),
      );

  Widget _templatePicker(Color accent, ColorScheme scheme) {
    return Column(
      children: [
        // Plantilla | Color
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Text('Plantilla', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 24, child: VerticalDivider(width: 28)),
              const Text('Color'),
              const SizedBox(width: 8),
              for (final c in Paper.backgrounds)
                GestureDetector(
                  onTap: () => setState(() => _paper = _paper.copyWith(background: c)),
                  child: Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: c == _paper.background ? 2.5 : 1,
                        color: c == _paper.background ? accent : Colors.black26,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final (g, _) in Paper.groups)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(g),
                    selected: g == _group,
                    showCheckmark: false,
                    selectedColor: accent.withValues(alpha: 0.1),
                    side: BorderSide(color: g == _group ? accent : Colors.transparent),
                    labelStyle: TextStyle(color: g == _group ? accent : null),
                    onSelected: (_) => _jumpTo(g),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (name, templates) in Paper.groups) ...[
                  Padding(
                    key: _groupKeys[name],
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(name, style: const TextStyle(fontSize: 17)),
                  ),
                  SizedBox(
                    height: 158,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: templates.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (context, i) {
                        final t = templates[i];
                        final selected = t == _paper.template;
                        return GestureDetector(
                          onTap: () => setState(() => _paper = _paper.copyWith(template: t)),
                          child: SizedBox(
                            width: 84,
                            child: Column(
                              children: [
                                Stack(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: selected ? accent : Colors.black12,
                                            width: selected ? 2 : 1),
                                        boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black12)],
                                      ),
                                      child: _page(_paper.copyWith(template: t), width: 84),
                                    ),
                                    if (selected) _check(accent),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(t.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12, color: selected ? accent : Colors.black54)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
