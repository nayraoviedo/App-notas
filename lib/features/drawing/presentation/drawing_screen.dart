import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/study_timer.dart';
import '../../notes/domain/note_block.dart';
import '../../settings/settings.dart';
import '../application/drawing_controller.dart';
import '../domain/drawing.dart';
import 'drawing_block_view.dart';
import 'painters/drawing_painter.dart';
import 'painters/paper_painter.dart';
import 'widgets/layers_sheet.dart';
import 'widgets/paper_sheet.dart';
import 'widgets/tool_settings_sheet.dart';

/// Hojas para escribir a mano y dibujar, con capas. Las hojas de una nota
/// forman un cuaderno: se puede pasar de página, ver miniaturas, marcar,
/// agregar, copiar y borrar páginas.
class DrawingScreen extends ConsumerStatefulWidget {
  const DrawingScreen({super.key, required this.noteId, required this.path});

  final String noteId;

  /// Archivo JSON de la hoja con la que se abre.
  final String path;

  @override
  ConsumerState<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends ConsumerState<DrawingScreen> {
  DrawingController? _ctl;
  final _transform = TransformationController();
  double? _fittedWidth;

  double _fitScale = 1;

  final _pointers = <int>{};
  int? _drawingPointer;

  /// Hoja abierta ahora.
  late String _path = widget.path;

  // Ajuste de figura: mantener quieto el lápiz al final del trazo.
  Timer? _holdTimer;
  Offset? _holdAnchor;

  @override
  void initState() {
    super.initState();
    _load(_path);
  }

  Future<void> _load(String path) async {
    final old = _ctl;
    if (old != null) {
      await old.flush();
      ref.invalidate(drawingFileProvider(_path));
    }
    final store = ref.read(drawingStoreProvider);
    final drawing = await store.load(path);
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    final keepTool = old?.tool;
    setState(() {
      _path = path;
      _fittedWidth = null; // volver a ajustar la hoja a la pantalla
      _ctl = DrawingController(drawing, onSave: (d) => store.save(path, d))
        ..stylusOnly = old?.stylusOnly ?? settings.stylusOnly;
      if (keepTool != null) _ctl!.selectTool(keepTool);
    });
    old?.dispose();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _ctl?.flush();
    _ctl?.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _ctl?.flush();
    ref.invalidate(drawingFileProvider(_path)); // refrescar la vista previa
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------- Páginas

  List<DrawingBlock> get _pages => (ref.read(blocksProvider(widget.noteId)).valueOrNull ??
          const <NoteBlock>[])
      .whereType<DrawingBlock>()
      .toList();

  int get _pageIndex => _pages.indexWhere((p) => p.path == _path);

  void _goTo(int index) {
    final pages = _pages;
    if (index < 0 || index >= pages.length) return;
    _load(pages[index].path);
  }

  Future<void> _addPage({required bool copy}) async {
    final ctl = _ctl;
    final pages = _pages;
    final i = _pageIndex;
    if (ctl == null || i < 0) return;
    await ctl.flush();
    final storage = ref.read(fileStorageProvider);
    final path = await storage.newDrawingPath();
    final d = ctl.drawing;
    final newDrawing = copy
        ? d.copyWith(bookmarked: false)
        // Página nueva con la misma hoja (plantilla, color, tamaño).
        : Drawing(
            width: d.width,
            height: d.height,
            // En prácticas de caligrafía: misma cuadrícula, sin caracteres.
            paper: d.paper.copyWith(
              clearImage: true,
              practice: d.paper.practice?.copyWith(chars: const []),
            ),
            layers: const [DrawingLayer(id: 'l1', name: 'Capa 1')],
          );
    await ref.read(drawingStoreProvider).save(path, newDrawing);
    await ref
        .read(notesRepositoryProvider)
        .insertDrawingBlockAfter(widget.noteId, pages[i].id, path);
    await _load(path);
  }

  Future<void> _deletePage() async {
    final pages = _pages;
    final i = _pageIndex;
    if (i < 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar esta página?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    final page = pages[i];
    await ref.read(notesRepositoryProvider).deleteBlock(page.id);
    await ref.read(fileStorageProvider).deleteIfExists(page.path);
    if (pages.length == 1) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await _load(pages[i == pages.length - 1 ? i - 1 : i + 1].path);
  }

  Future<void> _showThumbnails() async {
    await _ctl?.flush();
    ref.invalidate(drawingFileProvider(_path));
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: _ThumbnailsSheet(noteId: widget.noteId, currentPath: _path),
      ),
    );
    if (chosen != null && chosen != _path) await _load(chosen);
  }

  Future<void> _pageMenu() async {
    final ctl = _ctl!;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Agregar página después'),
              onTap: () => Navigator.pop(context, 'add'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copiar página'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.rotate_90_degrees_ccw_outlined),
              title: Text(ctl.drawing.isLandscape ? 'Poner vertical' : 'Poner horizontal'),
              onTap: () => Navigator.pop(context, 'rotate'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Borrar página'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'add':
        await _addPage(copy: false);
      case 'copy':
        await _addPage(copy: true);
      case 'rotate':
        ctl.setLandscape(!ctl.drawing.isLandscape);
      case 'delete':
        await _deletePage();
    }
  }

  // ------------------------------------------------------------------ Entrada

  bool _accepts(PointerEvent e) {
    final ctl = _ctl!;
    if (ctl.mode == InputMode.pan) return false;
    if (ctl.stylusOnly && e.kind != PointerDeviceKind.stylus) return false;
    return true;
  }

  double? _pressure(PointerEvent e) => DrawingController.normalizePressure(
        isStylus: e.kind == PointerDeviceKind.stylus,
        pressure: e.pressure,
        min: e.pressureMin,
        max: e.pressureMax,
      );

  void _onDown(PointerDownEvent e) {
    final ctl = _ctl!;
    _pointers.add(e.pointer);
    if (_pointers.length > 1) {
      // Segundo dedo: es un gesto de zoom, no un trazo.
      ctl.cancelStroke();
      _drawingPointer = null;
      _disarmHold();
      return;
    }
    if (!_accepts(e)) return;
    if (!ctl.canDrawOnActiveLayer) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('La capa activa está oculta o bloqueada')));
      return;
    }
    _drawingPointer = e.pointer;
    if (ctl.mode == InputMode.eraseStrokes) {
      ctl.beginEraseStrokes();
      ctl.eraseStrokesAt(e.localPosition);
    } else {
      final settings = ref.read(settingsProvider);
      // Con "grosor según zoom", al acercar la hoja el trazo sale más fino.
      final scale = _transform.value.getMaxScaleOnAxis();
      ctl.startStroke(
        e.localPosition,
        _pressure(e),
        sizeScale: settings.scaleWithZoom && scale > 0 ? _fitScale / scale : 1,
      );
      _armHold(e.localPosition);
    }
  }

  /// Si el lápiz se queda quieto ~0,6 s al final de un trazo, se intenta
  /// convertirlo en figura perfecta.
  void _armHold(Offset at) {
    if (!ref.read(settingsProvider).shapeSnap) return;
    if (_holdAnchor != null && (at - _holdAnchor!).distance < 4) return;
    _holdAnchor = at;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 600), () {
      if (_drawingPointer == null) return;
      final shape = _ctl?.snapCurrentStroke();
      if (shape != null) HapticFeedback.lightImpact();
    });
  }

  void _disarmHold() {
    _holdTimer?.cancel();
    _holdAnchor = null;
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _drawingPointer) return;
    final ctl = _ctl!;
    if (ctl.mode == InputMode.eraseStrokes) {
      ctl.eraseStrokesAt(e.localPosition);
    } else {
      ctl.extendStroke(e.localPosition, _pressure(e));
      _armHold(e.localPosition);
    }
  }

  void _onUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    _disarmHold();
    if (e.pointer != _drawingPointer) return;
    _drawingPointer = null;
    _ctl!.endStroke();
  }

  void _onCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    _disarmHold();
    if (e.pointer == _drawingPointer) {
      _drawingPointer = null;
      _ctl!.cancelStroke();
    }
  }

  // ---------------------------------------------------------------- Interfaz

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl;
    // Mantener la lista de páginas actualizada.
    final pages = (ref.watch(blocksProvider(widget.noteId)).valueOrNull ?? const <NoteBlock>[])
        .whereType<DrawingBlock>()
        .toList();
    final index = pages.indexWhere((p) => p.path == _path);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        appBar: AppBar(
          leading: BackButton(onPressed: _close),
          titleSpacing: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Página anterior',
                icon: const Icon(Icons.chevron_left),
                onPressed: index > 0 ? () => _goTo(index - 1) : null,
              ),
              GestureDetector(
                onTap: _showThumbnails,
                child: Text(
                  index < 0 ? '–' : '${index + 1}/${pages.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Página siguiente',
                icon: const Icon(Icons.chevron_right),
                onPressed: index >= 0 && index < pages.length - 1
                    ? () => _goTo(index + 1)
                    : null,
              ),
            ],
          ),
          actions: ctl == null
              ? null
              : [
                  const StudyTimerButton(),
                  ListenableBuilder(
                    listenable: ctl,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Deshacer',
                          icon: const Icon(Icons.undo),
                          onPressed: ctl.canUndo ? ctl.undo : null,
                        ),
                        IconButton(
                          tooltip: 'Rehacer',
                          icon: const Icon(Icons.redo),
                          onPressed: ctl.canRedo ? ctl.redo : null,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Capas',
                    icon: const Icon(Icons.layers_outlined),
                    onPressed: () => _sheet(LayersSheet(controller: ctl)),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (a) {
                      switch (a) {
                        case 'thumbs':
                          _showThumbnails();
                        case 'bookmark':
                          ctl.toggleBookmark();
                        case 'paper':
                          _sheet(PaperSheet(
                            controller: ctl,
                            onPickImage: ref.read(cameraServiceProvider).pickImageFromGallery,
                          ));
                        case 'page':
                          _pageMenu();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'thumbs',
                        child: ListTile(
                            leading: Icon(Icons.grid_view), title: Text('Miniaturas')),
                      ),
                      PopupMenuItem(
                        value: 'bookmark',
                        child: ListTile(
                          leading: Icon(ctl.drawing.bookmarked
                              ? Icons.bookmark
                              : Icons.bookmark_border),
                          title: Text(ctl.drawing.bookmarked
                              ? 'Quitar marcador'
                              : 'Marcar página'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'paper',
                        child: ListTile(
                            leading: Icon(Icons.description_outlined),
                            title: Text('Cambiar plantilla')),
                      ),
                      const PopupMenuItem(
                        value: 'page',
                        child: ListTile(
                            leading: Icon(Icons.auto_stories_outlined),
                            title: Text('Página: agregar, copiar, girar…')),
                      ),
                    ],
                  ),
                ],
        ),
        body: ctl == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(child: _canvas(ctl)),
                  _ToolBar(controller: ctl, onOpenSettings: () => _sheet(ToolSettingsSheet(controller: ctl))),
                ],
              ),
      ),
    );
  }

  Widget _canvas(DrawingController ctl) {
    return LayoutBuilder(
      builder: (context, c) {
        return ListenableBuilder(
          listenable: ctl,
          builder: (context, _) {
            final d = ctl.drawing;
            // Ajustar la hoja al ancho de la pantalla la primera vez (y al
            // girarla entre vertical/horizontal).
            final fitKey = c.maxWidth * 10000 + d.width;
            if (_fittedWidth != fitKey) {
              _fittedWidth = fitKey;
              final scale = (c.maxWidth - 16) / d.width;
              _fitScale = scale;
              _transform.value = Matrix4.identity()
                ..setEntry(0, 0, scale)
                ..setEntry(1, 1, scale)
                ..setEntry(0, 3, 8)
                ..setEntry(1, 3, 8);
            }
            return InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: 0.2,
              maxScale: 8,
              boundaryMargin: const EdgeInsets.all(400),
              panEnabled: ctl.mode == InputMode.pan || ctl.stylusOnly,
              child: Container(
                width: d.width,
                height: d.height,
                decoration: const BoxDecoration(
                  boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black26)],
                ),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onDown,
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  onPointerCancel: _onCancel,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: PaperView(paper: d.paper),
                      ),
                      RepaintBoundary(
                        child: CustomPaint(painter: DrawingPainter(ctl)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _sheet(Widget child) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: child,
        ),
      );
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.controller, required this.onOpenSettings});
  final DrawingController controller;
  final VoidCallback onOpenSettings;

  static const _icons = {
    ToolType.pen: Icons.edit,
    ToolType.pencil: Icons.create_outlined,
    ToolType.brush: Icons.brush,
    ToolType.marker: Icons.border_color,
    ToolType.highlighter: Icons.highlight,
    ToolType.eraser: Icons.auto_fix_normal,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final c = controller;
        Widget button({
          required IconData icon,
          required String tooltip,
          required bool selected,
          required VoidCallback onTap,
          Color? dot,
        }) =>
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  IconButton(
                    tooltip: tooltip,
                    isSelected: selected,
                    style: IconButton.styleFrom(
                      backgroundColor: selected ? scheme.primaryContainer : null,
                    ),
                    icon: Icon(icon),
                    onPressed: onTap,
                  ),
                  if (dot != null)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                ],
              ),
            );

        return Material(
          elevation: 8,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  for (final t in ToolType.values)
                    button(
                      icon: _icons[t]!,
                      tooltip: t.label,
                      selected: c.mode == InputMode.draw && c.tool == t,
                      dot: t == ToolType.eraser ? null : Color(c.settingsFor(t).color),
                      onTap: () {
                        // Tocar la herramienta ya elegida abre color y grosor.
                        if (c.mode == InputMode.draw && c.tool == t) {
                          onOpenSettings();
                        } else {
                          c.selectTool(t);
                        }
                      },
                    ),
                  const SizedBox(height: 32, child: VerticalDivider()),
                  button(
                    icon: Icons.cleaning_services_outlined,
                    tooltip: 'Borrar trazos completos',
                    selected: c.mode == InputMode.eraseStrokes,
                    onTap: () => c.selectMode(InputMode.eraseStrokes),
                  ),
                  button(
                    icon: Icons.pan_tool_outlined,
                    tooltip: 'Mover la hoja',
                    selected: c.mode == InputMode.pan,
                    onTap: () => c.selectMode(InputMode.pan),
                  ),
                  button(
                    icon: Icons.tune,
                    tooltip: 'Color y grosor',
                    selected: false,
                    onTap: onOpenSettings,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Miniaturas de todas las páginas de la nota, con filtro de marcadas.
class _ThumbnailsSheet extends ConsumerStatefulWidget {
  const _ThumbnailsSheet({required this.noteId, required this.currentPath});
  final String noteId;
  final String currentPath;

  @override
  ConsumerState<_ThumbnailsSheet> createState() => _ThumbnailsSheetState();
}

class _ThumbnailsSheetState extends ConsumerState<_ThumbnailsSheet> {
  bool _onlyBookmarked = false;

  @override
  Widget build(BuildContext context) {
    final pages = (ref.watch(blocksProvider(widget.noteId)).valueOrNull ?? const <NoteBlock>[])
        .whereType<DrawingBlock>()
        .toList();
    final entries = [
      for (var i = 0; i < pages.length; i++)
        if (!_onlyBookmarked ||
            (ref.watch(drawingFileProvider(pages[i].path)).valueOrNull?.bookmarked ?? false))
          (i, pages[i]),
    ];
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('Páginas', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilterChip(
                avatar: const Icon(Icons.bookmark, size: 16),
                label: const Text('Marcadas'),
                selected: _onlyBookmarked,
                onSelected: (v) => setState(() => _onlyBookmarked = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.62,
            ),
            itemCount: entries.length,
            itemBuilder: (context, k) {
              final (i, page) = entries[k];
              final current = page.path == widget.currentPath;
              return Column(
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          width: current ? 3 : 1,
                          color: current ? scheme.primary : scheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: DrawingBlockView(
                          block: page,
                          onOpen: () => Navigator.pop(context, page.path),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${i + 1}',
                      style: TextStyle(
                          color: current ? scheme.primary : null,
                          fontWeight: current ? FontWeight.w700 : null)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
