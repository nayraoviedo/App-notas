import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../camera/crop_screen.dart';

import '../../drawing/domain/drawing.dart';
import '../../drawing/presentation/painters/paper_painter.dart';
import '../../notebooks/domain/notebook.dart' show coverArts;
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
    this.coverDesign,
    this.coverArt,
    this.tags = const [],
  });

  /// Tapa ilustrada (nombre del dibujo) u obra de arte (ruta del asset).
  final String? coverDesign;
  final String? coverArt;

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
  bool get _plated => coverDesign != null || coverArt != null;

  Drawing coverPage() => Drawing(
        width: _w,
        height: _h,
        paper: PaperStyle(
          template: PaperTemplate.cover,
          background: coverColor,
          design: coverDesign,
          imagePath: coverArt,
        ),
        layers: [
          DrawingLayer(
            id: 'l1',
            name: 'Capa 1',
            items: [
              // En las tapas con placa, el título va en la placa ("NOTEBOOK"
              // si no hay título) y se puede editar tocándolo.
              if (_plated)
                TextItem(
                  id: 'cover-title',
                  x: _w / 2,
                  y: _h * 0.235,
                  text: title.trim().isEmpty ? 'NOTEBOOK' : title.trim().toUpperCase(),
                  font: 'Playfair Display',
                  size: 50,
                  bold: true,
                  color: 0xFF5D6B5A,
                  align: TextItemAlign.center,
                  width: _w * 0.4,
                )
              else if (title.trim().isNotEmpty)
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

class CreateNoteForm extends ConsumerStatefulWidget {
  const CreateNoteForm({super.key});

  @override
  ConsumerState<CreateNoteForm> createState() => _CreateNoteFormState();
}

class _CreateNoteFormState extends ConsumerState<CreateNoteForm> {
  final _title = TextEditingController();
  bool _withSheet = true;
  bool _withCover = true;
  bool _editingCover = false;
  // Tapa: una pintura de dominio público o una foto tuya.
  int _coverColor = 0xFFB9C6B0;
  String? _coverDesign;
  String? _coverArt = coverArts.first.asset;
  List<String> _myCovers = const [];

  @override
  void initState() {
    super.initState();
    _loadMyCovers();
  }

  Future<void> _loadMyCovers() async {
    try {
      final l = await ref.read(fileStorageProvider).listFolder('covers');
      if (mounted) setState(() => _myCovers = l);
    } catch (_) {}
  }

  /// Subir una tapa propia: foto de la galería, recortada.
  Future<void> _uploadCover() async {
    final picked = await pickAndCropImage(context, ref, camera: false);
    if (picked == null || !mounted) return;
    final path = await ref.read(fileStorageProvider).importFile(picked, folder: 'covers');
    await _loadMyCovers();
    setState(() {
      _coverArt = path;
      _coverDesign = null;
    });
  }

  PaperStyle get _coverPaper => PaperStyle(
        template: PaperTemplate.cover,
        background: _coverColor,
        design: _coverDesign,
        imagePath: _coverArt,
      );
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
                      coverDesign: _coverDesign,
                      coverArt: _coverArt,
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
                    label: 'Elegir tapa',
                    selected: _editingCover,
                    dashed: true,
                    onTap: () => setState(() {
                      _editingCover = true;
                      _withCover = true;
                    }),
                    child: Opacity(
                      opacity: _withCover ? 1 : 0.35,
                      child: _page(_coverPaper),
                    ),
                  ),
                  const SizedBox(width: 8),
                  card(
                    label: 'Elegir hoja',
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
                                  'Con tapa',
                                  Switch(
                                    value: _withCover,
                                    onChanged: (v) => setState(() {
                                      _withCover = v;
                                      if (!v) _editingCover = false;
                                    }),
                                  ),
                                ),
                              row(
                                'Hoja',
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
                                'Para',
                                DropdownButton<bool>(
                                  value: _withSheet,
                                  underline: const SizedBox.shrink(),
                                  isDense: true,
                                  items: const [
                                    DropdownMenuItem(value: true, child: Text('Escribir a mano')),
                                    DropdownMenuItem(value: false, child: Text('Solo texto')),
                                  ],
                                  onChanged: (v) => setState(() => _withSheet = v ?? true),
                                ),
                              ),
                            ],
        ),
      );

  Widget _coverPicker(Color accent) {
    // Pinturas de dominio público, tus fotos y un botón para subir otra.
    final options = <(String, String?)>[
      for (final a in coverArts) (a.asset, a.artist),
      for (final m in _myCovers) (m, 'Mía'),
    ];
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.62,
      ),
      itemCount: options.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return GestureDetector(
            onTap: _uploadCover,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: accent, width: 1.5),
                      color: accent.withValues(alpha: 0.06),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, color: accent, size: 30),
                        const SizedBox(height: 4),
                        Text('Subir\nfoto', textAlign: TextAlign.center, style: TextStyle(color: accent)),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Text('Tu tapa', style: TextStyle(fontSize: 10.5, color: Colors.black54)),
                ),
              ],
            ),
          );
        }
        final (art, label) = options[i - 1];
        final selected = art == _coverArt;
        final paper = PaperStyle(template: PaperTemplate.cover, background: _coverColor, imagePath: art);
        return GestureDetector(
          onTap: () => setState(() {
            _coverDesign = null;
            _coverArt = art;
          }),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: selected ? accent : Colors.black12, width: selected ? 2.5 : 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(width: _pageW, height: _pageH, child: PaperView(paper: paper)),
                      ),
                    ),
                    if (selected) _check(accent),
                  ],
                ),
              ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
                ),
            ],
          ),
        );
      },
    );
  }

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
