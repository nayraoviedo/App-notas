import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../drawing/domain/drawing.dart';
import '../../export/pdf_exporter.dart';
import '../../drawing/presentation/drawing_block_view.dart';
import '../domain/note_block.dart';

/// Colores de las pestañas (tonos suaves, como un planner).
const tabColors = <int>[
  0xFF3E6A80, 0xFF8FB3C6, 0xFFD9CBB4, 0xFFE8C17A, 0xFFE59C8B, 0xFF9DB58A, 0xFFB7A3D6, 0xFF2F3F4F,
];

/// Leer una nota como un cuaderno: se hojea pasando el dedo (la hoja gira
/// sobre el lomo), con pestañas de colores al costado para saltar a una
/// sección y pestañas abajo para agregar hojas o editar.
class BookViewScreen extends ConsumerStatefulWidget {
  const BookViewScreen({super.key, required this.noteId, this.initialPage = 0});
  final String noteId;
  final int initialPage;

  @override
  ConsumerState<BookViewScreen> createState() => _BookViewScreenState();
}

class _BookViewScreenState extends ConsumerState<BookViewScreen> with SingleTickerProviderStateMixin {
  /// Posición de lectura: 2.4 = pasando de la página 3 a la 4 (base 0).
  late double _pos = widget.initialPage.toDouble();
  late final AnimationController _anim = AnimationController(vsync: this)
    ..addListener(() => setState(() => _pos = _tween?.evaluate(_anim) ?? _pos));
  Tween<double>? _tween;
  double _dragStart = 0;
  double _dragPos = 0;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  List<DrawingBlock> get _pages =>
      (ref.read(blocksProvider(widget.noteId)).valueOrNull ?? const <NoteBlock>[])
          .whereType<DrawingBlock>()
          .toList();

  int get _current => _pos.round();

  void _animateTo(double target, {double velocity = 0}) {
    final n = _pages.length;
    target = target.clamp(0, math.max(0, n - 1)).toDouble();
    _tween = Tween(begin: _pos, end: target);
    final dist = (target - _pos).abs();
    _anim.duration = Duration(milliseconds: (220 + 260 * math.min(dist, 3)).round());
    _anim.forward(from: 0);
  }

  void _goTo(int page) => _animateTo(page.toDouble());

  Future<void> _edit() async {
    final pages = _pages;
    if (pages.isEmpty) return;
    await context.push('/notes/${widget.noteId}/drawing', extra: pages[_current].path);
    ref.invalidate(drawingFileProvider(pages[_current].path));
  }

  Future<void> _addPage(PaperTemplate template) async {
    final pages = _pages;
    if (pages.isEmpty) return;
    final cur = pages[_current];
    final store = ref.read(drawingStoreProvider);
    final base = await store.load(cur.path);
    final path = await ref.read(fileStorageProvider).newDrawingPath();
    await store.save(
      path,
      Drawing(
        width: base.paper.template == PaperTemplate.cover ? Drawing.a4Width : base.width,
        height: base.paper.template == PaperTemplate.cover ? Drawing.a4Height : base.height,
        paper: PaperStyle(template: template),
        layers: const [DrawingLayer(id: 'l1', name: 'Capa 1')],
      ),
    );
    await ref.read(notesRepositoryProvider).insertDrawingBlockAfter(widget.noteId, cur.id, path);
    // Esperar a que la lista se actualice y pasar a la hoja nueva.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted) _goTo(_current + 1);
  }

  Future<void> _editTab(DrawingBlock page) async {
    final store = ref.read(drawingStoreProvider);
    final d = await store.load(page.path);
    if (!mounted) return;
    final result = await showDialog<(String?, int?)>(
      context: context,
      builder: (context) => _TabDialog(initial: d.tab, color: d.tabColor),
    );
    if (result == null) return;
    final (name, color) = result;
    final next = name == null || name.trim().isEmpty
        ? d.copyWith(clearTab: true)
        : d.copyWith(tab: name.trim(), tabColor: color);
    await store.save(page.path, next);
    ref.invalidate(drawingFileProvider(page.path));
  }

  @override
  Widget build(BuildContext context) {
    final note = ref.watch(noteProvider(widget.noteId)).valueOrNull;
    final pages = (ref.watch(blocksProvider(widget.noteId)).valueOrNull ?? const <NoteBlock>[])
        .whereType<DrawingBlock>()
        .toList();
    if (pages.isNotEmpty && _pos > pages.length - 1) _pos = (pages.length - 1).toDouble();
    final drawings = [for (final p in pages) ref.watch(drawingFileProvider(p.path)).valueOrNull];

    return Scaffold(
      backgroundColor: const Color(0xFFD5E0E6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD5E0E6),
        title: Text(note?.displayTitle ?? ''),
        actions: [
          IconButton(
            tooltip: 'Ver bloques (audios, textos, videos)',
            icon: const Icon(Icons.view_agenda_outlined),
            onPressed: () => context.push('/notes/${widget.noteId}'),
          ),
          IconButton(
            tooltip: 'Exportar el cuaderno a PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => exportNoteToPdf(ref, widget.noteId),
          ),
          IconButton(tooltip: 'Editar esta página', icon: const Icon(Icons.edit_outlined), onPressed: _edit),
        ],
      ),
      body: pages.isEmpty
          ? const Center(child: Text('Esta nota todavía no tiene hojas.'))
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 0, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _binder(pages)),
                          _SideTabs(
                            pages: pages,
                            drawings: drawings,
                            current: _current,
                            onTap: _goTo,
                            onLongPress: _editTab,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _bottomTabs(pages),
                ],
              ),
            ),
    );
  }

  /// La carpeta del cuaderno con la hoja que se hojea.
  Widget _binder(List<DrawingBlock> pages) {
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) {
          _anim.stop();
          _dragStart = d.localPosition.dx;
          _dragPos = _pos;
        },
        onHorizontalDragUpdate: (d) {
          final delta = (_dragStart - d.localPosition.dx) / (width * 0.8);
          setState(() => _pos = (_dragPos + delta).clamp(0, pages.length - 1).toDouble());
        },
        onHorizontalDragEnd: (d) {
          final v = -(d.primaryVelocity ?? 0) / width;
          final target = v.abs() > 0.6
              ? (v > 0 ? _pos.floorToDouble() + 1 : _pos.ceilToDouble() - 1)
              : _pos.roundToDouble();
          _animateTo(target);
        },
        onTap: _edit,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF2F5363),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(blurRadius: 10, offset: Offset(0, 4), color: Color(0x33000000))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ColoredBox(
              color: const Color(0xFFF8F6F1),
              child: _flipper(pages),
            ),
          ),
        ),
      );
    });
  }

  Widget _flipper(List<DrawingBlock> pages) {
    final base = _pos.floor().clamp(0, pages.length - 1);
    final t = (_pos - base).clamp(0.0, 1.0);
    Widget page(int i) => Center(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: IgnorePointer(child: DrawingBlockView(block: pages[i], onOpen: () {})),
          ),
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        // Hoja de abajo (la que aparece), un poco sombreada mientras gira la otra.
        if (base + 1 < pages.length && t > 0)
          Stack(
            fit: StackFit.expand,
            children: [
              page(base + 1),
              IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: 0.18 * (1 - t)))),
            ],
          ),
        // Hoja que gira sobre el lomo (borde izquierdo).
        Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(-t * math.pi / 2),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: const Color(0xFFF8F6F1), child: page(base)),
              // Brillo/sombra del papel al doblarse.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.25 * t),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Número de página.
        Positioned(
          bottom: 8,
          right: 12,
          child: Text('${_current + 1} / ${pages.length}',
              style: const TextStyle(fontSize: 12, color: Colors.black38)),
        ),
      ],
    );
  }

  Widget _bottomTabs(List<DrawingBlock> pages) {
    Widget tab(String label, Color color, VoidCallback onTap, {Color text = Colors.white}) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Material(
            color: color,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
            child: InkWell(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Text(label.toUpperCase(),
                    style: TextStyle(
                        color: text, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              ),
            ),
          ),
        );
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        children: [
          tab('Índice', const Color(0xFF3E6A80), () => _index(pages)),
          tab('Pestaña', const Color(0xFF8FB3C6), () => _editTab(pages[_current])),
          tab('Editar', const Color(0xFFD9CBB4), _edit, text: const Color(0xFF3B2A22)),
          const SizedBox(width: 14),
          tab('Blanca', const Color(0xFF3E6A80), () => _addPage(PaperTemplate.blank)),
          tab('Puntos', const Color(0xFF8FB3C6), () => _addPage(PaperTemplate.dots)),
          tab('Cuadrícula', const Color(0xFF5E8AA0), () => _addPage(PaperTemplate.grid)),
          tab('Rayada', const Color(0xFFD9CBB4), () => _addPage(PaperTemplate.lined),
              text: const Color(0xFF3B2A22)),
        ],
      ),
    );
  }

  Future<void> _index(List<DrawingBlock> pages) async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 130,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.62,
          ),
          itemCount: pages.length,
          itemBuilder: (context, i) => Column(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: i == _current ? const Color(0xFF2F5363) : Colors.black12,
                        width: i == _current ? 2.5 : 1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: DrawingBlockView(block: pages[i], onOpen: () => Navigator.pop(context, i)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('${i + 1}'),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) _goTo(chosen);
  }
}

/// Pestañas verticales al costado derecho (una por página con pestaña).
class _SideTabs extends StatelessWidget {
  const _SideTabs({
    required this.pages,
    required this.drawings,
    required this.current,
    required this.onTap,
    required this.onLongPress,
  });

  final List<DrawingBlock> pages;
  final List<Drawing?> drawings;
  final int current;
  final ValueChanged<int> onTap;
  final ValueChanged<DrawingBlock> onLongPress;

  @override
  Widget build(BuildContext context) {
    // La sección actual es la última pestaña en o antes de la página actual.
    var section = -1;
    for (var i = 0; i <= current && i < drawings.length; i++) {
      if (drawings[i]?.tab != null) section = i;
    }
    final tabs = [
      for (var i = 0; i < pages.length; i++)
        if (drawings[i]?.tab != null) i,
    ];
    return SizedBox(
      width: 34,
      child: ListView(
        padding: const EdgeInsets.only(top: 18, bottom: 18),
        children: [
          for (final i in tabs)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: GestureDetector(
                onTap: () => onTap(i),
                onLongPress: () => onLongPress(pages[i]),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 54),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == section
                        ? const Color(0xFF1F3440)
                        : Color(drawings[i]!.tabColor ?? tabColors[1]),
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(9)),
                  ),
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      drawings[i]!.tab!.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: _onColor(i == section ? 0xFF1F3440 : (drawings[i]!.tabColor ?? tabColors[1])),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Agregar pestaña a la página actual.
          Tooltip(
            message: 'Poner pestaña en esta página',
            child: GestureDetector(
              onTap: () => onLongPress(pages[current]),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(9)),
                ),
                child: const Icon(Icons.add, size: 18, color: Color(0xFF2F5363)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _onColor(int c) => Color(c).computeLuminance() > 0.5 ? const Color(0xFF2F3F4F) : Colors.white;
}

class _TabDialog extends StatefulWidget {
  const _TabDialog({this.initial, this.color});
  final String? initial;
  final int? color;

  @override
  State<_TabDialog> createState() => _TabDialogState();
}

class _TabDialogState extends State<_TabDialog> {
  late final _name = TextEditingController(text: widget.initial ?? '');
  late int _color = widget.color ?? tabColors.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Pestaña de la página'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 14,
              decoration: const InputDecoration(hintText: 'NOV, Biología, Tareas…'),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in tabColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(c),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          width: c == _color ? 3 : 1,
                          color: c == _color ? Theme.of(context).colorScheme.primary : Colors.black12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          if (widget.initial != null)
            TextButton(onPressed: () => Navigator.pop(context, (null, null)), child: const Text('Quitar')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (_name.text, _color)),
            child: const Text('Guardar'),
          ),
        ],
      );
}
