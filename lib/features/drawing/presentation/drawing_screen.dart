import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/study_timer.dart';
import '../../notes/domain/note_block.dart';
import '../../notes/presentation/note_tags_dialog.dart';
import '../../recording/application/recording_controller.dart';
import '../../settings/settings.dart';
import '../application/drawing_controller.dart';
import '../domain/drawing.dart';
import 'drawing_block_view.dart';
import 'widgets/canvas_item_view.dart';
import 'widgets/text_item_editor.dart';
import '../../camera/crop_screen.dart';
import 'painters/drawing_painter.dart';
import 'painters/paper_painter.dart';
import 'widgets/layers_sheet.dart';
import 'widgets/paper_sheet.dart';
import 'painters/sticker_painter.dart';
import 'widgets/tool_panels.dart';

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

  // Textos y fotos (collage).
  final _pageKey = GlobalKey();
  Size _viewport = Size.zero;
  bool _pointerOnItem = false;
  Offset? _tapStart;

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
        ? d.copyWith(bookmarked: false, clearTab: true)
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
    if (ctl.mode == InputMode.text || ctl.mode == InputMode.select) {
      _tapStart = _pointers.length == 1 ? e.localPosition : null;
      return;
    }
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
    if (_ctl!.mode == InputMode.text || _ctl!.mode == InputMode.select) return;
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
    final ctl = _ctl!;
    if (ctl.mode == InputMode.text || ctl.mode == InputMode.select) {
      final start = _tapStart;
      final onItem = _pointerOnItem;
      _tapStart = null;
      _pointerOnItem = false;
      if (onItem || start == null || (e.localPosition - start).distance > 12) return;
      // Toque en un espacio vacío.
      if (ctl.selectedItemId != null) {
        ctl.selectItem(null);
      } else if (ctl.mode == InputMode.text) {
        _newText(e.localPosition);
      }
      return;
    }
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

  // --------------------------------------------------------- Barra superior

  ToolPanel _panel = ToolPanel.none;
  bool _toolbarOpen = true;

  /// Última pluma usada (fuente, bolígrafo, pincel…).
  ToolType _pen = ToolType.pen;

  void _togglePanel(ToolPanel p) => setState(() => _panel = _panel == p ? ToolPanel.none : p);

  void _closePanel() {
    if (_panel != ToolPanel.none) setState(() => _panel = ToolPanel.none);
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl;
    // Mantener la lista de páginas actualizada.
    final pages = (ref.watch(blocksProvider(widget.noteId)).valueOrNull ?? const <NoteBlock>[])
        .whereType<DrawingBlock>()
        .toList();
    final index = pages.indexWhere((p) => p.path == _path);
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE9ECEF),
        body: ctl == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Material(
                    color: scheme.surface,
                    elevation: 1,
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          _topRow(ctl),
                          if (_toolbarOpen) ...[
                            const Divider(height: 1),
                            _toolRow(ctl),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: _canvas(ctl)),
                        // Número de página (toca para ver miniaturas).
                        Positioned(
                          bottom: 14,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.12),
                              shape: const StadiumBorder(),
                              child: InkWell(
                                customBorder: const StadiumBorder(),
                                onTap: _showThumbnails,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                                  child: Text(
                                    index < 0 ? '–' : '${index + 1}/${pages.length}',
                                    style: const TextStyle(fontSize: 16, color: Colors.black54),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Pasar de página.
                        Positioned(
                          right: 8,
                          bottom: 60,
                          child: Material(
                            color: scheme.surface.withValues(alpha: 0.9),
                            shape: const StadiumBorder(),
                            elevation: 2,
                            child: Column(
                              children: [
                                IconButton(
                                  tooltip: 'Página anterior',
                                  icon: const Icon(Icons.keyboard_arrow_up),
                                  onPressed: index > 0 ? () => _goTo(index - 1) : null,
                                ),
                                IconButton(
                                  tooltip: index >= 0 && index < pages.length - 1
                                      ? 'Página siguiente'
                                      : 'Agregar página',
                                  icon: Icon(index >= 0 && index < pages.length - 1
                                      ? Icons.keyboard_arrow_down
                                      : Icons.add),
                                  onPressed: index >= 0 && index < pages.length - 1
                                      ? () => _goTo(index + 1)
                                      : () => _addPage(copy: false),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_panel != ToolPanel.none) ...[
                          // Tocar fuera cierra el panel.
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _closePanel,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            left: 12,
                            right: 12,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 400),
                                child: _panelFor(ctl),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ListenableBuilder(
                    listenable: ctl,
                    builder: (context, _) => ctl.selectedItem != null
                        ? _ItemBar(
                            controller: ctl,
                            onEditText: _editText,
                            onEditShape: () => setState(() => _panel = ToolPanel.shapes),
                            onCrop: _cropImageItem,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _icon(IconData icon, String tooltip, VoidCallback? onTap, {bool selected = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: selected ? scheme.primaryContainer.withValues(alpha: 0.6) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, size: 24),
        onPressed: onTap,
      ),
    );
  }

  /// Fila 1: volver, cámara, grabar, páginas, capas, hoja, página nueva,
  /// etiquetas, más opciones y ocultar herramientas.
  Widget _topRow(DrawingController ctl) {
    final rec = ref.watch(recordingControllerProvider);
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          _icon(Icons.arrow_back_ios_new, 'Volver', _close),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _icon(Icons.photo_camera_outlined, 'Poner una foto', () {
                    _closePanel();
                    _chooseImageSource();
                  }),
                  if (rec.isActive || rec.status == RecordingStatus.processing)
                    _RecordingPill(state: rec, onStop: _stopRecording)
                  else
                    _icon(Icons.mic_none, 'Grabar audio mientras escribes', _startRecording),
                  const SizedBox(width: 6),
                  _icon(Icons.auto_stories_outlined, 'Páginas', _showThumbnails),
                  _icon(Icons.layers_outlined, 'Capas', () {
                    _closePanel();
                    _sheet(LayersSheet(controller: ctl));
                  }),
                  _icon(Icons.description_outlined, 'Plantilla de la hoja', () {
                    _closePanel();
                    _sheet(PaperSheet(
                      controller: ctl,
                      onPickImage: ref.read(cameraServiceProvider).pickImageFromGallery,
                    ));
                  }),
                  _icon(Icons.note_add_outlined, 'Agregar página', () => _addPage(copy: false)),
                  _icon(Icons.tag, 'Etiquetas', () => showNoteTagsDialog(context, ref, widget.noteId)),
                  const StudyTimerButton(),
                  _icon(Icons.more_horiz, 'Más', () {
                    _closePanel();
                    _moreMenu(ctl);
                  }),
                ],
              ),
            ),
          ),
          _icon(_toolbarOpen ? Icons.expand_less : Icons.expand_more,
              _toolbarOpen ? 'Ocultar herramientas' : 'Mostrar herramientas',
              () => setState(() {
                    _toolbarOpen = !_toolbarOpen;
                    _panel = ToolPanel.none;
                  })),
        ],
      ),
    );
  }

  /// Fila 2: deshacer/rehacer, herramientas y colores rápidos.
  Widget _toolRow(DrawingController ctl) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final c = ctl;
        if (penTools.contains(c.tool)) _pen = c.tool;
        final drawing = c.mode == InputMode.draw;
        final penOn = drawing && penTools.contains(c.tool);
        final hlOn = drawing && c.tool == ToolType.highlighter;
        final eraserOn =
            (drawing && c.tool == ToolType.eraser) || c.mode == InputMode.eraseStrokes;
        final showColors = penOn || hlOn;
        return SizedBox(
          height: 54,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                _icon(Icons.undo, 'Deshacer', c.canUndo ? c.undo : null),
                _icon(Icons.redo, 'Rehacer', c.canRedo ? c.redo : null),
                const SizedBox(height: 30, child: VerticalDivider(width: 10)),
                _icon(toolIcon(_pen), _pen.label, () {
                  if (penOn) {
                    _togglePanel(ToolPanel.pen);
                  } else {
                    c.selectTool(_pen);
                    _closePanel();
                  }
                }, selected: penOn),
                _icon(Icons.highlight, 'Resaltador', () {
                  if (hlOn) {
                    _togglePanel(ToolPanel.highlighter);
                  } else {
                    c.selectTool(ToolType.highlighter);
                    _closePanel();
                  }
                }, selected: hlOn),
                _icon(Icons.auto_fix_normal, 'Borrador', () {
                  if (eraserOn) {
                    _togglePanel(ToolPanel.eraser);
                  } else {
                    c.selectTool(ToolType.eraser);
                    _closePanel();
                  }
                }, selected: eraserOn),
                _icon(Icons.highlight_alt, 'Seleccionar y mover', () {
                  c.selectMode(InputMode.select);
                  _closePanel();
                }, selected: c.mode == InputMode.select),
                _icon(Icons.text_fields, 'Texto: toca la hoja para escribir', () {
                  c.selectMode(InputMode.text);
                  _closePanel();
                }, selected: c.mode == InputMode.text),
                _icon(Icons.category_outlined, 'Formas', () => _togglePanel(ToolPanel.shapes),
                    selected: _panel == ToolPanel.shapes),
                _icon(Icons.emoji_emotions_outlined, 'Stickers',
                    () => _togglePanel(ToolPanel.stickers),
                    selected: _panel == ToolPanel.stickers),
                if (showColors) ...[
                  const SizedBox(height: 30, child: VerticalDivider(width: 14)),
                  SizedBox(
                    width: 200,
                    child: QuickColorRow(
                      size: 32,
                      colors: c.quickColors(c.tool),
                      selected: c.settings.color,
                      onPick: c.setColor,
                      onReplace: c.setQuickColor,
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

  Widget _panelFor(DrawingController ctl) => switch (_panel) {
        ToolPanel.pen => PenPanel(controller: ctl),
        ToolPanel.highlighter => HighlighterPanel(controller: ctl),
        ToolPanel.eraser => EraserPanel(controller: ctl),
        ToolPanel.shapes => ShapesPanel(controller: ctl, onInsert: _insertShape),
        ToolPanel.stickers => StickersPanel(
            onSticker: _insertSticker,
            onTextSticker: _insertTextSticker,
            onEmoji: _insertEmoji,
          ),
        ToolPanel.none => const SizedBox.shrink(),
      };

  Future<void> _moreMenu(DrawingController ctl) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Hojear como cuaderno'),
              onTap: () => Navigator.pop(context, 'book'),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: Text(ctl.drawing.tab == null
                  ? 'Poner pestaña en esta página'
                  : 'Pestaña: ${ctl.drawing.tab}'),
              onTap: () => Navigator.pop(context, 'tab'),
            ),
            ListTile(
              leading: Icon(ctl.drawing.bookmarked ? Icons.bookmark : Icons.bookmark_border),
              title: Text(ctl.drawing.bookmarked ? 'Quitar marcador' : 'Marcar página'),
              onTap: () => Navigator.pop(context, 'bookmark'),
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
            SwitchListTile(
              secondary: const Icon(Icons.pan_tool_outlined),
              title: const Text('Mover la hoja con un dedo'),
              subtitle: const Text('Con dos dedos siempre se mueve y hace zoom'),
              value: ctl.mode == InputMode.pan,
              onChanged: (_) => Navigator.pop(context, 'pan'),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.edit_note),
              title: const Text('Solo lápiz óptico'),
              value: ctl.stylusOnly,
              onChanged: (_) => Navigator.pop(context, 'stylus'),
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
      case 'book':
        await ctl.flush();
        if (!mounted) return;
        final i = _pageIndex;
        await context.push('/notes/${widget.noteId}/book', extra: i < 0 ? 0 : i);
      case 'tab':
        final name = TextEditingController(text: ctl.drawing.tab ?? '');
        final r = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Pestaña de la página'),
            content: TextField(
              controller: name,
              autofocus: true,
              maxLength: 14,
              decoration: const InputDecoration(hintText: 'NOV, Biología, Tareas…'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Quitar')),
              FilledButton(onPressed: () => Navigator.pop(context, name.text), child: const Text('Guardar')),
            ],
          ),
        );
        if (r != null) ctl.setTab(r, color: ctl.drawing.tabColor ?? 0xFF3E6A80);
      case 'bookmark':
        ctl.toggleBookmark();
      case 'copy':
        await _addPage(copy: true);
      case 'rotate':
        ctl.setLandscape(!ctl.drawing.isLandscape);
      case 'stylus':
        ctl.toggleStylusOnly();
      case 'pan':
        ctl.mode == InputMode.pan ? ctl.selectTool(_pen) : ctl.selectMode(InputMode.pan);
      case 'delete':
        await _deletePage();
    }
  }

  // ------------------------------------------------- Grabar mientras escribes

  Future<void> _startRecording() async {
    final rec = ref.read(recordingControllerProvider.notifier);
    await rec.start(widget.noteId);
    final st = ref.read(recordingControllerProvider);
    if (!mounted || st.status != RecordingStatus.error) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(st.message ?? 'No se pudo empezar a grabar'),
      action: st.micBlocked
          ? SnackBarAction(label: 'Abrir ajustes', onPressed: openAppSettings)
          : null,
    ));
  }

  Future<void> _stopRecording() async {
    final rec = ref.read(recordingControllerProvider);
    if (!rec.isActive) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Guardando y transcribiendo… el audio queda en la nota')));
    await ref.read(recordingControllerProvider.notifier).stop();
    final msg = ref.read(recordingControllerProvider).message;
    if (mounted && msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ---------------------------------------------------- Stickers y formas

  void _placeAndSelect(CanvasItem item) {
    final ctl = _ctl!;
    if (!ctl.canDrawOnActiveLayer) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La capa activa está oculta o bloqueada')));
      return;
    }
    ctl.addItem(item);
    ctl.selectMode(InputMode.select);
    ctl.selectItem(item.id);
    _closePanel();
  }

  /// Recortar una foto que ya está en la hoja (mantiene su ancho).
  Future<void> _cropImageItem(ImageItem it) async {
    final out = await cropImage(context, it.path);
    if (out == null || !mounted) return;
    final buffer = await ui.ImmutableBuffer.fromFilePath(out);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final w = desc.width.toDouble(), h = desc.height.toDouble();
    desc.dispose();
    buffer.dispose();
    _ctl?.updateItem(
      it.id,
      (_) => ImageItem(
        id: it.id,
        x: it.x,
        y: it.y,
        scale: it.scale,
        rotation: it.rotation,
        path: out,
        width: it.width,
        height: it.width * h / w,
        frame: it.frame,
      ),
    );
  }

  void _insertSticker(StickerDef def) {
    final c = _visibleCenter;
    _placeAndSelect(StickerItem(
      id: DrawingController.newItemId(),
      x: c.dx,
      y: c.dy,
      sticker: def.id,
      width: def.width,
      height: def.height,
    ));
  }

  void _insertTextSticker(TextSticker t) {
    final c = _visibleCenter;
    _placeAndSelect(TextItem(
      id: DrawingController.newItemId(),
      x: c.dx,
      y: c.dy,
      text: t.text,
      font: t.font,
      size: 64,
      color: t.color,
      background: t.background,
      width: 800,
    ));
  }

  void _insertEmoji(String e) {
    final c = _visibleCenter;
    _placeAndSelect(TextItem(
      id: DrawingController.newItemId(),
      x: c.dx,
      y: c.dy,
      text: e,
      size: 110,
      width: 300,
    ));
  }

  void _insertShape(ShapeKind kind) {
    final ctl = _ctl!;
    final c = _visibleCenter;
    final (w, h) = kind.defaultSize;
    _placeAndSelect(ShapeItem(
      id: DrawingController.newItemId(),
      x: c.dx,
      y: c.dy,
      shape: kind,
      width: w,
      height: h,
      color: ctl.shapeColor,
      strokeWidth: ctl.shapeStrokeWidth,
      fill: ctl.shapeFill && !kind.isLine ? ShapesPanel.fillFor(ctl.shapeColor) : null,
    ));
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
            _viewport = Size(c.maxWidth, c.maxHeight);
            return InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: 0.2,
              maxScale: 8,
              boundaryMargin: const EdgeInsets.all(400),
              panEnabled: ctl.mode == InputMode.pan || ctl.stylusOnly,
              child: Container(
                key: _pageKey,
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
                      // Cada capa: sus trazos y encima sus textos y fotos.
                      for (var i = 0; i < d.layers.length; i++)
                        if (d.layers[i].visible) ...[
                          RepaintBoundary(
                            child: CustomPaint(painter: LayerPainter(ctl, i)),
                          ),
                          if (d.layers[i].items.isNotEmpty)
                            Opacity(
                              opacity: d.layers[i].opacity,
                              child: IgnorePointer(
                                // Los elementos solo se tocan con "Texto" o "Mover".
                                ignoring: !(ctl.mode == InputMode.select ||
                                        ctl.mode == InputMode.text) ||
                                    d.layers[i].locked,
                                child: Stack(
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    for (final it in d.layers[i].items)
                                      EditableCanvasItem(
                                        key: ValueKey(it.id),
                                        item: it,
                                        controller: ctl,
                                        pageKey: _pageKey,
                                        onEditText: _editText,
                                        onPointerDown: () => _pointerOnItem = true,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
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

  // ------------------------------------------------------- Textos y fotos

  /// Último estilo usado, para que el siguiente texto salga igual.
  TextItem? _lastTextStyle;

  Future<void> _newText(Offset at) async {
    final ctl = _ctl!;
    if (!ctl.canDrawOnActiveLayer) return;
    final base = (_lastTextStyle ??
            const TextItem(id: '', x: 0, y: 0, text: '', font: 'Dancing Script', size: 40))
        .copyWith(text: '', x: at.dx, y: at.dy, scale: 1, rotation: 0);
    final draft = TextItem(
      id: DrawingController.newItemId(),
      x: at.dx,
      y: at.dy,
      text: '',
      font: base.font,
      size: base.size,
      color: base.color,
      bold: base.bold,
      italic: base.italic,
      align: base.align,
      background: base.background,
      width: base.width,
    );
    final result = await showTextItemEditor(context, draft);
    if (result == null || result.text.trim().isEmpty) return;
    _lastTextStyle = result;
    ctl.addItem(result);
  }

  Future<void> _editText(TextItem item) async {
    final result = await showTextItemEditor(context, item);
    if (result == null) return;
    final ctl = _ctl!;
    if (result.text.trim().isEmpty) {
      ctl.removeItem(item.id);
      return;
    }
    _lastTextStyle = result;
    ctl.updateItem(item.id, (_) => result);
  }

  /// Centro de lo que se ve ahora, en coordenadas de la hoja.
  Offset get _visibleCenter {
    final d = _ctl!.drawing;
    if (_viewport == Size.zero) return Offset(d.width / 2, d.height / 2);
    final p = _transform.toScene(_viewport.center(Offset.zero));
    return Offset(p.dx.clamp(0, d.width).toDouble(), p.dy.clamp(0, d.height).toDouble());
  }

  Future<void> _addImage({required bool camera}) async {
    final ctl = _ctl!;
    if (!ctl.canDrawOnActiveLayer) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La capa activa está oculta o bloqueada')));
      return;
    }
    final path = await pickAndCropImage(context, ref, camera: camera, forNoteId: widget.noteId);
    if (path == null) return;
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final w = desc.width.toDouble(), h = desc.height.toDouble();
    desc.dispose();
    buffer.dispose();
    // Tamaño inicial: que entre en ~la mitad de la hoja.
    final k = 480 / (w > h ? w : h);
    final c = _visibleCenter;
    ctl.addItem(ImageItem(
      id: DrawingController.newItemId(),
      x: c.dx,
      y: c.dy,
      path: path,
      width: w * k,
      height: h * k,
    ));
    ctl.selectMode(InputMode.select);
    ctl.selectItem(ctl.drawing.layers[ctl.activeLayerIndex].items.last.id);
  }

  Future<void> _chooseImageSource() async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (camera != null) await _addImage(camera: camera);
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

/// Acciones para el texto o la foto seleccionada.
class _ItemBar extends StatelessWidget {
  const _ItemBar({
    required this.controller,
    required this.onEditText,
    required this.onEditShape,
    required this.onCrop,
  });
  final DrawingController controller;
  final void Function(TextItem item) onEditText;
  final void Function(ImageItem item) onCrop;
  final VoidCallback onEditShape;

  @override
  Widget build(BuildContext context) {
    final item = controller.selectedItem!;
    Widget action(IconData icon, String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(icon), Text(label, style: const TextStyle(fontSize: 11))],
            ),
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
              if (item is TextItem)
                action(Icons.edit_outlined, 'Editar', () => onEditText(item))
              else if (item is ShapeItem)
                action(Icons.palette_outlined, 'Estilo', onEditShape)
              else if (item is ImageItem) ...[
                action(Icons.crop, 'Recortar', () => onCrop(item)),
                PopupMenuButton<ImageFrame>(
                  tooltip: 'Marco',
                  onSelected: (f) => controller.updateItem(
                      item.id, (it) => (it as ImageItem).withFrame(f)),
                  itemBuilder: (_) => [
                    for (final f in ImageFrame.values)
                      PopupMenuItem(value: f, child: Text(f.label)),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(Icons.filter_frames_outlined), Text('Marco', style: TextStyle(fontSize: 11))],
                    ),
                  ),
                ),
              ],
              action(Icons.copy_outlined, 'Duplicar', () => controller.duplicateItem(item.id)),
              action(Icons.flip_to_front, 'Al frente',
                  () => controller.reorderItem(item.id, toFront: true)),
              action(Icons.flip_to_back, 'Atrás',
                  () => controller.reorderItem(item.id, toFront: false)),
              action(Icons.restart_alt, 'Enderezar',
                  () => controller.updateItem(item.id, (it) => it.moved(rotation: 0))),
              action(Icons.delete_outline, 'Borrar', () => controller.removeItem(item.id)),
              action(Icons.check, 'Listo', () => controller.selectItem(null)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Píldora roja de "grabando" con el tiempo; tocar para terminar.
class _RecordingPill extends StatelessWidget {
  const _RecordingPill({required this.state, required this.onStop});
  final RecordingState state;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFE0409A);
    final processing = state.status == RecordingStatus.processing;
    final secs = state.elapsedMs ~/ 1000;
    final label = processing
        ? '${(state.progressLabel ?? '').startsWith('Descargando') ? 'Bajando modelo' : 'Transcribiendo'} ${state.progress}%'
        : '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.white,
        shape: const StadiumBorder(side: BorderSide(color: Color(0x22000000))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: processing ? null : onStop,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (processing)
                  const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: pink, width: 2),
                    ),
                    child: Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            color: pink, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(color: pink, fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
