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

/// Leer una nota como un cuaderno: la hoja grande, se hojea deslizando; al
/// costado los separadores que pone cada uno (tocar uno lleva a su hoja);
/// abajo ◀ n/N ▶ y "+ Hoja"; arriba el índice con miniaturas.
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

  /// Hoja nueva después de la actual, del mismo tipo (después de la tapa:
  /// rayada).
  Future<void> _addPage() async {
    final pages = _pages;
    if (pages.isEmpty) return;
    final cur = pages[_current];
    final store = ref.read(drawingStoreProvider);
    final base = await store.load(cur.path);
    final template =
        base.paper.template == PaperTemplate.cover ? PaperTemplate.lined : base.paper.template;
    final path = await ref.read(fileStorageProvider).newDrawingPath();
    await store.save(
      path,
      Drawing(
        width: base.paper.template == PaperTemplate.cover ? Drawing.a4Width : base.width,
        height: base.paper.template == PaperTemplate.cover ? Drawing.a4Height : base.height,
        paper: base.paper.template == PaperTemplate.cover
            ? PaperStyle(template: template)
            : base.paper.copyWith(clearImage: true),
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
      backgroundColor: const Color(0xFFF3EEE6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3EEE6),
        title: Text(note?.displayTitle ?? ''),
        actions: [
          IconButton(
            tooltip: 'Índice de hojas',
            icon: const Icon(Icons.format_list_numbered),
            onPressed: pages.isEmpty ? null : () => _index(pages, drawings),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'blocks') context.push('/notes/${widget.noteId}');
              if (v == 'export') exportNoteFlow(context, ref, widget.noteId);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export',
                child: ListTile(leading: Icon(Icons.ios_share), title: Text('Exportar a PDF o Word')),
              ),
              PopupMenuItem(
                value: 'blocks',
                child: ListTile(
                    leading: Icon(Icons.view_agenda_outlined), title: Text('Audios, textos y videos de la nota')),
              ),
            ],
          ),
          IconButton(tooltip: 'Escribir en esta hoja', icon: const Icon(Icons.edit_outlined), onPressed: _edit),
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
                      padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
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
                  _bottomBar(pages),
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(blurRadius: 12, offset: Offset(0, 4), color: Color(0x26000000))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
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

      ],
    );
  }

  /// Abajo: ◀ 5 / 12 ▶ (tocar el número abre el índice) y "+ Hoja".
  Widget _bottomBar(List<DrawingBlock> pages) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Hoja anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: _current > 0 ? () => _goTo(_current - 1) : null,
          ),
          TextButton(
            onPressed: () => _index(pages, [for (final p in pages) ref.read(drawingFileProvider(p.path)).valueOrNull]),
            child: Text('${_current + 1} / ${pages.length}', style: TextStyle(fontSize: 17, color: ink)),
          ),
          IconButton(
            tooltip: 'Hoja siguiente',
            icon: const Icon(Icons.chevron_right),
            onPressed: _current < pages.length - 1 ? () => _goTo(_current + 1) : null,
          ),
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: _addPage,
            icon: const Icon(Icons.add),
            label: const Text('Hoja'),
          ),
        ],
      ),
    );
  }

  /// Índice: miniaturas numeradas, agrupadas por separador.
  Future<void> _index(List<DrawingBlock> pages, List<Drawing?> drawings) async {
    // Secciones: cada separador empieza una; lo de antes es "Inicio".
    final sections = <(String, int?, List<int>)>[];
    for (var i = 0; i < pages.length; i++) {
      final tab = drawings.length > i ? drawings[i]?.tab : null;
      if (tab != null || sections.isEmpty) {
        sections.add((tab ?? 'Inicio', tab == null ? null : drawings[i]?.tabColor ?? tabColors[1], []));
      }
      sections.last.$3.add(i);
    }
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text('Índice', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              ),
            ),
            for (final (name, color, idx) in sections) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: color == null ? Colors.black12 : Color(color),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Text('· ${idx.length} ${idx.length == 1 ? 'hoja' : 'hojas'}',
                          style: const TextStyle(color: Colors.black45)),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 100,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.66,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    childCount: idx.length,
                    (context, k) {
                      final i = idx[k];
                      return GestureDetector(
                        onTap: () => Navigator.pop(context, i),
                        child: Column(
                          children: [
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: i == _current ? Theme.of(context).colorScheme.primary : Colors.black12,
                                      width: i == _current ? 2.5 : 1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: IgnorePointer(child: DrawingBlockView(block: pages[i], onOpen: () {})),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text('${i + 1}', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
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
      width: 36,
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
                      drawings[i]!.tab!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _onColor(i == section ? 0xFF1F3440 : (drawings[i]!.tabColor ?? tabColors[1])),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Agregar pestaña a la página actual.
          Tooltip(
            message: 'Poner un separador en esta hoja',
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
        title: const Text('Separador de esta hoja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 18,
              decoration: const InputDecoration(hintText: 'Redes lógicas, Parcial 1, Tareas…'),
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
