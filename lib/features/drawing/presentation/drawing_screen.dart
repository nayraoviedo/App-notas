import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
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
import 'widgets/table_equation.dart';
import 'widgets/tool_panels.dart';

/// Hojas para escribir a mano y dibujar, con capas. Las hojas de una nota
/// forman un cuaderno: se puede pasar de página, ver miniaturas, marcar,
/// agregar, copiar y borrar páginas.
class DrawingScreen extends ConsumerStatefulWidget {
  const DrawingScreen({super.key, required this.noteId, required this.path, this.embedded = false});

  final String noteId;

  /// Dentro de otra pantalla (debajo del video): sin botón de volver.
  final bool embedded;

  /// Archivo JSON de la hoja con la que se abre.
  final String path;

  @override
  ConsumerState<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends ConsumerState<DrawingScreen> with SingleTickerProviderStateMixin {
  DrawingController? _ctl;
  final _transform = TransformationController();
  double? _fittedWidth;

  double _fitScale = 1;

  final _pointers = <int>{};

  // Lazo
  bool _lassoing = false;
  bool _movingSel = false;
  Offset? _moveLast;
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

  // ------------------------------------------------ Deslizar entre hojas

  /// Animación al pasar de hoja (la nueva entra deslizándose).
  late final _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);
  int _slideDir = 1;

  // Seguimiento de un deslizamiento con un dedo (cuando el dedo no dibuja).
  int? _swipePointer;
  Offset _swipeStart = Offset.zero;
  DateTime _swipeTime = DateTime(0);
  int _swipeFingers = 0;

  bool get _atFit => _transform.value.getMaxScaleOnAxis() <= _fitScale * 1.08;

  /// Pasar de hoja tirando hacia arriba/abajo (por defecto) o deslizando de
  /// lado (Ajustes → Pasar de hoja).
  bool get _vertical => (ref.read(sharedPreferencesProvider).getString('pages.mode') ?? 'vertical') == 'vertical';

  /// Cuánto se tiró hacia arriba en la última hoja (1 = suelta para agregar).
  double _pull = 0;

  bool get _onLastPage {
    final i = _pageIndex;
    return i >= 0 && i == _pages.length - 1;
  }

  /// ¿El dedo tocó fuera de la hoja (en el fondo gris)? Ahí siempre se puede
  /// tirar o deslizar, aunque se esté dibujando con el dedo.
  bool _outsidePage(Offset global) {
    final box = _pageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final r = Rect.fromPoints(box.localToGlobal(Offset.zero), box.localToGlobal(box.size.bottomRight(Offset.zero)));
    return !r.contains(global);
  }

  /// Pasar a la hoja siguiente (+1) o anterior (-1).
  Future<void> _turn(int dir) async {
    final i = _pageIndex;
    final pages = _pages;
    final target = i + dir;
    if (i < 0 || target < 0 || target >= pages.length) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(target < 0 ? 'Es la primera hoja' : 'Es la última hoja'),
          action: target < 0
              ? null
              : SnackBarAction(label: 'Agregar hoja', onPressed: () => _addPage(copy: false)),
        ));
      return;
    }
    HapticFeedback.selectionClick();
    _slideDir = dir;
    await _load(pages[target].path);
    if (mounted) _slide.forward(from: 0);
  }

  void _swipeDown(PointerDownEvent e) {
    _swipeFingers++;
    final ctl = _ctl;
    // Solo cuando el dedo no está dibujando: modo mano o "solo lápiz".
    final fingerFree = ctl != null &&
        (ctl.mode == InputMode.pan || (ctl.stylusOnly && e.kind != PointerDeviceKind.stylus));
    if (_swipeFingers == 1 && (fingerFree || _outsidePage(e.position)) && _atFit && _editing == null) {
      _swipePointer = e.pointer;
      _swipeStart = e.position;
      _swipeTime = DateTime.now();
    } else {
      _swipePointer = null;
    }
  }

  void _swipeMove(PointerMoveEvent e) {
    if (e.pointer != _swipePointer || !_vertical || !_onLastPage) return;
    final dy = e.position.dy - _swipeStart.dy;
    final p = (-dy / 160).clamp(0.0, 1.25);
    if ((p - _pull).abs() > 0.02) setState(() => _pull = p);
  }

  Future<void> _swipeUp(PointerEvent e) async {
    _swipeFingers = (_swipeFingers - 1).clamp(0, 10);
    if (e.pointer != _swipePointer) return;
    _swipePointer = null;
    final d = e.position - _swipeStart;
    final pulled = _pull;
    if (_pull != 0) setState(() => _pull = 0);
    if (_vertical) {
      if (d.dy.abs() < 70 || d.dx.abs() > d.dy.abs() * 0.7) return;
      if (d.dy < 0 && _onLastPage) {
        // Tirar hacia arriba en la última hoja: agregar una nueva.
        if (pulled >= 1) {
          HapticFeedback.mediumImpact();
          _slideDir = 1;
          await _addPage(copy: false);
          if (mounted) _slide.forward(from: 0);
        }
        return;
      }
      await _turn(d.dy < 0 ? 1 : -1);
      return;
    }
    final fast = DateTime.now().difference(_swipeTime) < const Duration(milliseconds: 700);
    if (fast && d.dx.abs() > 70 && d.dy.abs() < d.dx.abs() * 0.6) await _turn(d.dx < 0 ? 1 : -1);
  }

  /// Aviso de "Tira para agregar una nueva página" (abajo, en la última hoja).
  Widget _pullHint() {
    final ready = _pull >= 1;
    final color = ready ? const Color(0xFF1E8CB4) : Colors.black45;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 56,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: _pull > 0 ? 1 : 0.55,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(0, -10 * _pull),
                child: Icon(Icons.arrow_upward_rounded, color: color, size: 22 + 6 * _pull),
              ),
              Icon(Icons.note_add, color: color, size: 30 + 8 * _pull.clamp(0, 1)),
              const SizedBox(height: 4),
              Text(ready ? 'Suelta para agregar la página' : 'Tira hacia arriba para agregar una página',
                  style: TextStyle(color: color, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  /// Franja en el borde: deslizar desde ahí cambia de hoja aunque estés
  /// dibujando con el dedo.
  Widget _edgeSwipe({required bool left}) => Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: 0,
        bottom: 0,
        width: 18,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (left && v > 150) _turn(-1);
            if (!left && v < -150) _turn(1);
          },
        ),
      );

  Future<void> _load(String path) async {
    if (_editing != null) _commitEditing();
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
    _slide.dispose();
    _holdTimer?.cancel();
    if (_fullscreen) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _editCtl.dispose();
    _editFocus.dispose();
    _ctl?.flush();
    _ctl?.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_editing != null) {
      _commitEditing();
      return; // el primer "atrás" solo termina el texto
    }
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
      // Lazo: en "Seleccionar", tocar fuera de textos/fotos dibuja el lazo
      // o, si se toca dentro de lo ya seleccionado, lo mueve.
      if (ctl.mode == InputMode.select && !_pointerOnItem) {
        if (_pointers.length > 1) {
          ctl.cancelLasso();
          _lassoing = false;
          _movingSel = false;
          return;
        }
        final b = ctl.selectionBounds;
        if (b != null && b.inflate(24).contains(e.localPosition)) {
          _movingSel = true;
          _moveLast = e.localPosition;
          ctl.beginItemChange();
        } else {
          _lassoing = true;
          ctl.selectItem(null);
          ctl.beginLasso(e.localPosition);
        }
      }
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
    if (_ctl!.mode == InputMode.select) {
      if (_movingSel && _moveLast != null) {
        _ctl!.moveSelection(e.localPosition - _moveLast!);
        _moveLast = e.localPosition;
      } else if (_lassoing) {
        _ctl!.extendLasso(e.localPosition);
      }
      return;
    }
    if (_ctl!.mode == InputMode.text) return;
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
    if (ctl.mode == InputMode.select && (_lassoing || _movingSel)) {
      final start = _tapStart;
      final moved = start != null && (e.localPosition - start).distance > 12;
      if (_lassoing) {
        moved ? ctl.endLasso() : ctl.clearStrokeSelection();
      }
      _lassoing = false;
      _movingSel = false;
      _moveLast = null;
      _tapStart = null;
      _pointerOnItem = false;
      return;
    }
    if (ctl.mode == InputMode.text || ctl.mode == InputMode.select) {
      final start = _tapStart;
      final onItem = _pointerOnItem;
      _tapStart = null;
      _pointerOnItem = false;
      if (onItem || start == null || (e.localPosition - start).distance > 12) return;
      // Tocar fuera del texto que se escribe: terminarlo.
      if (_editing != null) {
        _commitEditing();
        return;
      }
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
  bool _fullscreen = false;

  void _setFullscreen(bool on) {
    setState(() {
      _fullscreen = on;
      _panel = ToolPanel.none;
    });
    SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

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
                  if (!_fullscreen)
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
                        Positioned.fill(
                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: _swipeDown,
                            onPointerMove: _swipeMove,
                            onPointerUp: _swipeUp,
                            onPointerCancel: _swipeUp,
                            child: AnimatedBuilder(
                              animation: _slide,
                              builder: (context, child) {
                                final v = Curves.easeOutCubic.transform(_slide.value);
                                final off = _slideDir * (1 - v) * 140;
                                return Transform.translate(
                                  offset: _vertical ? Offset(0, off) : Offset(off, 0),
                                  child: Opacity(opacity: 0.35 + 0.65 * v, child: child),
                                );
                              },
                              child: _canvas(ctl),
                            ),
                          ),
                        ),
                        if (_editing == null && !_vertical) ...[
                          _edgeSwipe(left: true),
                          _edgeSwipe(left: false),
                        ],
                        if (_vertical && _onLastPage && _editing == null) _pullHint(),
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
                                  onPressed: index > 0 ? () => _turn(-1) : null,
                                ),
                                IconButton(
                                  tooltip: index >= 0 && index < pages.length - 1
                                      ? 'Página siguiente'
                                      : 'Agregar página',
                                  icon: Icon(index >= 0 && index < pages.length - 1
                                      ? Icons.keyboard_arrow_down
                                      : Icons.add),
                                  onPressed: index >= 0 && index < pages.length - 1
                                      ? () => _turn(1)
                                      : () => _addPage(copy: false),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_fullscreen)
                          Positioned(
                            top: MediaQuery.paddingOf(context).top + 8,
                            right: 8,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: const CircleBorder(),
                              child: IconButton(
                                tooltip: 'Salir de pantalla completa',
                                icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                                onPressed: () => _setFullscreen(false),
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
                  if (_editing != null)
                    TextStyleBar(
                      item: _editing!,
                      onChanged: (t) => setState(() => _editing = t),
                      onDone: _commitEditing,
                    )
                  else
                  ListenableBuilder(
                    listenable: ctl,
                    builder: (context, _) => ctl.hasStrokeSelection
                        ? _StrokeSelectionBar(controller: ctl)
                        : ctl.selectedItem != null
                        ? _ItemBar(
                            controller: ctl,
                            onEditText: _editText,
                            onEditShape: () => setState(() => _panel = ToolPanel.shapes),
                            onCrop: _cropImageItem,
                            onEditSource: (it) =>
                                _tableOrEquation(table: decodeSource(it.source) is TableData, editing: it),
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
    final title = ref.watch(noteProvider(widget.noteId)).valueOrNull?.displayTitle ?? '';
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          if (!widget.embedded) _icon(Icons.arrow_back_ios_new, 'Volver', _close),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ),
          if (rec.isActive || rec.status == RecordingStatus.processing)
            _RecordingPill(state: rec, onStop: _openRecorder)
          else if (_audios(watch: true).isNotEmpty)
            // Grabaciones de esta nota (con su transcripción y resumen).
            Badge(
              label: Text('${_audios().length}'),
              offset: const Offset(-4, 4),
              child: _icon(Icons.graphic_eq, 'Grabaciones y transcripciones', _showRecordings),
            ),
          const StudyTimerButton(),
          // Insertar: todo lo que se agrega a la hoja, con nombre.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 38),
              ),
              onPressed: () => _insertMenu(ctl),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Insertar'),
            ),
          ),
          _icon(Icons.auto_stories_outlined, 'Hojas', _showThumbnails),
          _icon(Icons.more_vert, 'Más', () {
            _closePanel();
            _moreMenu(ctl);
          }),
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

  /// Panel "Insertar": íconos grandes con su nombre.
  Future<void> _insertMenu(DrawingController ctl) async {
    _closePanel();
    final recording = ref.read(recordingControllerProvider).isActive;
    final items = <(IconData, String, String)>[
      (Icons.photo_camera_outlined, 'Foto', 'photo'),
      (Icons.mic_none, recording ? 'Grabando…' : 'Grabar audio', 'rec'),
      (Icons.table_chart_outlined, 'Tabla', 'table'),
      (Icons.functions, 'Ecuación', 'eq'),
      (Icons.category_outlined, 'Formas', 'shapes'),
      (Icons.emoji_emotions_outlined, 'Stickers', 'stickers'),
      (Icons.text_fields, 'Texto', 'text'),
      (Icons.note_add_outlined, 'Hoja nueva', 'page'),
    ];
    final a = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.95,
            children: [
              for (final (icon, label, id) in items)
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(context, id),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(icon, size: 26, color: Theme.of(context).colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: 6),
                      Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (a) {
      case 'photo':
        _chooseImageSource();
      case 'rec':
        recording ? _openRecorder() : await _startRecording();
      case 'table':
        await _tableOrEquation(table: true);
      case 'eq':
        await _tableOrEquation(table: false);
      case 'shapes':
        setState(() => _panel = ToolPanel.shapes);
      case 'stickers':
        setState(() => _panel = ToolPanel.stickers);
      case 'text':
        ctl.selectMode(InputMode.text);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Toca la hoja donde quieras escribir'), duration: Duration(seconds: 2)));
      case 'page':
        await _addPage(copy: false);
    }
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
        final tapeOn = drawing && c.tool == ToolType.tape;
        final eraserOn =
            (drawing && c.tool == ToolType.eraser) || c.mode == InputMode.eraseStrokes;
        final showColors = penOn || hlOn || tapeOn;
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
                _icon(Icons.linear_scale, 'Cinta washi', () {
                  if (tapeOn) {
                    _togglePanel(ToolPanel.tape);
                  } else {
                    c.selectTool(ToolType.tape);
                    _closePanel();
                  }
                }, selected: tapeOn),
                _icon(Icons.auto_fix_normal, 'Borrador', () {
                  if (eraserOn) {
                    _togglePanel(ToolPanel.eraser);
                  } else {
                    c.selectTool(ToolType.eraser);
                    _closePanel();
                  }
                }, selected: eraserOn),
                _icon(Icons.highlight_alt, 'Lazo: rodea trazos para moverlos; toca textos y fotos para editarlos', () {
                  c.selectMode(InputMode.select);
                  _closePanel();
                }, selected: c.mode == InputMode.select),
                _icon(Icons.text_fields, 'Texto: toca la hoja para escribir', () {
                  c.selectMode(InputMode.text);
                  _closePanel();
                }, selected: c.mode == InputMode.text),
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
        ToolPanel.tape => HighlighterPanel(controller: ctl, tool: ToolType.tape),
        ToolPanel.eraser => EraserPanel(controller: ctl),
        ToolPanel.shapes => ShapesPanel(controller: ctl, onInsert: _insertShape),
        ToolPanel.stickers => StickersPanel(
            onSticker: _insertSticker,
            onTextSticker: _insertTextSticker,
            onEmoji: _insertEmoji,
            custom: ref.watch(customStickersProvider).valueOrNull ?? const [],
            onCustom: _insertCustomSticker,
            onAddCustom: _addCustomSticker,
            onDeleteCustom: _deleteCustomSticker,
            onAsset: _insertAssetSticker,
          ),
        ToolPanel.none => const SizedBox.shrink(),
      };

  Future<void> _moreMenu(DrawingController ctl) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Tipo de hoja (rayada, cuadros, color…)'),
              onTap: () => Navigator.pop(context, 'paper'),
            ),
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Capas'),
              onTap: () => Navigator.pop(context, 'layers'),
            ),
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: const Text('Etiquetas de la nota'),
              onTap: () => Navigator.pop(context, 'tags'),
            ),
            ListTile(
              leading: const Icon(Icons.fullscreen),
              title: const Text('Pantalla completa'),
              onTap: () => Navigator.pop(context, 'full'),
            ),
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
      )),
    );
    switch (action) {
      case 'paper':
        _sheet(PaperSheet(
          controller: ctl,
          onPickImage: ref.read(cameraServiceProvider).pickImageFromGallery,
        ));
      case 'layers':
        _sheet(LayersSheet(controller: ctl));
      case 'tags':
        await showNoteTagsDialog(context, ref, widget.noteId);
      case 'full':
        _setFullscreen(true);
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

  /// El micrófono abre la pantalla de grabación (con el texto en vivo);
  /// se puede minimizar y seguir escribiendo en la hoja.
  Future<void> _startRecording() async {
    _closePanel();
    await _ctl?.flush();
    if (!mounted) return;
    context.push('/notes/${widget.noteId}/record');
  }

  /// Tocar la pastilla roja: volver a la grabación (o a su transcripción).
  void _openRecorder() {
    final st = ref.read(recordingControllerProvider);
    if (st.status == RecordingStatus.processing && st.savedBlockId != null) {
      context.push('/notes/${widget.noteId}/audio/${st.savedBlockId}');
    } else {
      context.push('/notes/${widget.noteId}/record');
    }
  }

  /// Grabaciones de la nota ([watch] solo dentro de build).
  List<AudioBlock> _audios({bool watch = false}) =>
      ((watch ? ref.watch(blocksProvider(widget.noteId)) : ref.read(blocksProvider(widget.noteId)))
                  .valueOrNull ??
              const <NoteBlock>[])
          .whereType<AudioBlock>()
          .toList();

  /// Lista de grabaciones de la nota: tocar una abre su transcripción,
  /// resumen y el botón "Transcribir ahora".
  Future<void> _showRecordings() async {
    _closePanel();
    final blocks = _audios();
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Grabaciones de esta nota', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Toca una para ver la transcripción, el resumen o transcribirla'),
            ),
            for (final (i, b) in blocks.indexed)
              Consumer(builder: (context, ref, _) {
                final segs = ref.watch(segmentsProvider(b.id)).valueOrNull ?? const [];
                final preview = segs.take(2).map((s) => s.text).join(' ');
                final busy = ref.watch(recordingControllerProvider).status == RecordingStatus.processing &&
                    ref.watch(recordingControllerProvider).savedBlockId == b.id;
                return ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text('Grabación ${i + 1} · ${formatMs(b.durationMs)}'),
                  subtitle: Text(
                    busy ? 'Transcribiendo…' : (preview.isEmpty ? 'Sin transcripción (toca para transcribir)' : preview),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, b.id),
                );
              }),
          ],
        ),
      ),
    );
    if (id != null && mounted) context.push('/notes/${widget.noteId}/audio/$id');
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

  /// Insertar (o editar) una tabla o una ecuación: se dibuja como imagen y
  /// guarda sus datos para poder editarla otra vez.
  Future<void> _tableOrEquation({required bool table, ImageItem? editing}) async {
    _closePanel();
    final old = decodeSource(editing?.source);
    final Widget view;
    final String source;
    if (table) {
      final data = await editTable(context, old is TableData ? old : null);
      if (data == null || !mounted) return;
      view = TableView(data);
      source = data.encode();
    } else {
      final data = await editEquation(context, old is EquationData ? old : null);
      if (data == null || !mounted) return;
      view = EquationView(data);
      source = data.encode();
    }
    final (png, size) = await renderWidgetToPng(context, view);
    final path = await ref.read(fileStorageProvider).saveBytes(png, folder: 'images');
    if (!mounted) return;
    // Tamaño en la hoja (1000 de ancho): como se ve en pantalla, sin pasarse.
    var w = size.width * 1.2, h = size.height * 1.2;
    if (w > 900) {
      h = h * 900 / w;
      w = 900;
    }
    if (editing != null) {
      _ctl?.updateItem(
        editing.id,
        (_) => ImageItem(
          id: editing.id,
          x: editing.x,
          y: editing.y,
          scale: editing.scale,
          rotation: editing.rotation,
          path: path,
          width: w,
          height: h,
          source: source,
        ),
      );
      return;
    }
    final c = _visibleCenter;
    _placeAndSelect(ImageItem(
      id: DrawingController.newItemId(),
      x: c.dx,
      y: c.dy,
      path: path,
      width: w,
      height: h,
      source: source,
    ));
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

  /// Sticker de gatito incluido en la app: se copia a las imágenes de la
  /// nota para que también se exporte y se respalde como cualquier foto.
  Future<void> _insertAssetSticker(String asset) async {
    final data = await rootBundle.load(asset);
    final path = await ref
        .read(fileStorageProvider)
        .saveBytes(data.buffer.asUint8List(), folder: 'images');
    await _placeImageFile(path, maxSide: 200);
  }

  Future<void> _insertCustomSticker(String source) async {
    // Copia propia para la hoja: así borrar el sticker de "Míos" no la afecta.
    final path = await ref.read(fileStorageProvider).importFile(source, folder: 'images');
    await _placeImageFile(path);
  }

  Future<void> _placeImageFile(String path, {double maxSide = 260}) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final w = desc.width.toDouble(), h = desc.height.toDouble();
    desc.dispose();
    buffer.dispose();
    if (!mounted) return;
    final k = maxSide / (w > h ? w : h);
    final c = _visibleCenter;
    _placeAndSelect(ImageItem(
      id: DrawingController.newItemId(),
      x: c.dx,
      y: c.dy,
      path: path,
      width: w * k,
      height: h * k,
    ));
  }

  /// Agregar un sticker propio: una imagen de la galería (mejor si es PNG
  /// con fondo transparente), recortada.
  Future<void> _addCustomSticker() async {
    final picked = await ref.read(cameraServiceProvider).pickImageFromGallery();
    if (picked == null || !mounted) return;
    final cropped = await cropImage(context, picked);
    await ref.read(fileStorageProvider).importFile(cropped ?? picked, folder: 'stickers');
    ref.invalidate(customStickersProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Sticker agregado a "Míos" ✓')));
  }

  Future<void> _deleteCustomSticker(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Quitar este sticker de "Míos"?'),
        content: const Text('Los que ya pusiste en tus hojas no se borran.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(fileStorageProvider).deleteIfExists(path);
    ref.invalidate(customStickersProvider);
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
                                      if (it.id != _editing?.id)
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
                      if (ctl.lasso != null || ctl.hasStrokeSelection)
                        IgnorePointer(child: CustomPaint(painter: _LassoPainter(ctl.lasso, ctl.selectionBounds))),
                      if (_editing != null) _editingField(_editing!),
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

  // ---- Texto escrito directo sobre la hoja (sin cuadro aparte) ----

  /// Texto que se está escribiendo ahora (null = ninguno).
  TextItem? _editing;
  bool _editingIsNew = false;

  /// Esquina superior izquierda del cuadro, en coordenadas de la hoja.
  Offset _editTopLeft = Offset.zero;
  final _editCtl = TextEditingController();
  final _editFocus = FocusNode();

  void _newText(Offset at) {
    final ctl = _ctl!;
    if (!ctl.canDrawOnActiveLayer) return;
    final base = _lastTextStyle ??
        const TextItem(id: '', x: 0, y: 0, text: '', font: 'Dancing Script', size: 40);
    final d = ctl.drawing;
    final item = TextItem(
      id: DrawingController.newItemId(),
      x: at.dx,
      y: at.dy,
      text: '',
      font: base.font,
      size: base.size,
      color: base.color,
      bold: base.bold,
      italic: base.italic,
      underline: base.underline,
      strike: base.strike,
      align: base.align,
      lineHeight: base.lineHeight,
      background: base.background,
      // Que el cuadro no se salga de la hoja.
      width: (d.width - at.dx - 20).clamp(160.0, 700.0),
    );
    _startEditing(item, isNew: true, topLeft: Offset(at.dx, at.dy - item.size * 0.7));
  }

  void _editText(TextItem item) {
    final size = measureTextItem(item);
    final w = size.width * item.scale, h = size.height * item.scale;
    final boxW = item.width * item.scale;
    final left = switch (item.align) {
      TextItemAlign.left => item.x - w / 2,
      TextItemAlign.center => item.x - boxW / 2,
      TextItemAlign.right => item.x + w / 2 - boxW,
    };
    _startEditing(item, isNew: false, topLeft: Offset(left, item.y - h / 2));
  }

  void _startEditing(TextItem item, {required bool isNew, required Offset topLeft}) {
    _ctl?.selectItem(null);
    setState(() {
      _editing = item;
      _editingIsNew = isNew;
      _editTopLeft = topLeft;
      _panel = ToolPanel.none;
    });
    _editCtl.text = item.text;
    _editCtl.selection = TextSelection.collapsed(offset: item.text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocus.requestFocus();
      _revealEditing();
    });
  }

  /// Si el cuadro queda donde lo tapa el teclado, sube la hoja.
  void _revealEditing() {
    if (_viewport == Size.zero) return;
    final m = _transform.value;
    final p = MatrixUtils.transformPoint(m, _editTopLeft);
    final target = _viewport.height * 0.22;
    if (p.dy > _viewport.height * 0.4 || p.dy < 0) {
      _transform.value = m.clone()..setEntry(1, 3, m.entry(1, 3) + (target - p.dy));
    }
  }

  void _commitEditing() {
    final item = _editing;
    final ctl = _ctl;
    if (item == null || ctl == null) return;
    final text = _editCtl.text;
    final done = item.copyWith(text: text);
    setState(() => _editing = null);
    _editFocus.unfocus();
    if (text.trim().isEmpty) {
      if (!_editingIsNew) ctl.removeItem(item.id);
      return;
    }
    // Dejar el texto justo donde se escribió (se guarda por su centro).
    final size = measureTextItem(done);
    final w = size.width * done.scale, h = size.height * done.scale;
    final boxW = done.width * done.scale;
    final cx = switch (done.align) {
      TextItemAlign.left => _editTopLeft.dx + w / 2,
      TextItemAlign.center => _editTopLeft.dx + boxW / 2,
      TextItemAlign.right => _editTopLeft.dx + boxW - w / 2,
    };
    final placed = done.copyWith(x: cx, y: _editTopLeft.dy + h / 2);
    _lastTextStyle = placed;
    if (_editingIsNew) {
      ctl.addItem(placed);
      ctl.selectItem(null);
    } else {
      ctl.updateItem(item.id, (_) => placed);
    }
  }

  /// El cuadro de texto transparente sobre la hoja.
  Widget _editingField(TextItem item) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: _editTopLeft.dx,
      top: _editTopLeft.dy,
      child: Listener(
        onPointerDown: (_) => _pointerOnItem = true,
        child: Transform.scale(
          scale: item.scale,
          alignment: Alignment.topLeft,
          child: Container(
            width: item.width,
            padding: textItemPadding(item),
            decoration: BoxDecoration(
              color: item.background == null ? null : Color(item.background!),
              borderRadius: BorderRadius.circular(item.size * 0.2),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.7), width: 2),
            ),
            child: TextField(
              controller: _editCtl,
              focusNode: _editFocus,
              maxLines: null,
              textAlign: textItemAlign(item),
              style: textItemStyle(item),
              cursorColor: scheme.primary,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Escribe aquí…',
              ),
            ),
          ),
        ),
      ),
    );
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
    required this.onEditSource,
  });
  final DrawingController controller;
  final void Function(ImageItem item) onEditSource;
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
              else if (item is ImageItem && item.source != null)
                action(Icons.edit_outlined, 'Editar', () => onEditSource(item))
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
          onTap: onStop,
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

/// Dibuja el lazo y el recuadro de lo seleccionado.
class _LassoPainter extends CustomPainter {
  _LassoPainter(this.lasso, this.bounds);
  final List<Offset>? lasso;
  final Rect? bounds;

  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..color = const Color(0xFF1E8CB4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    void dashed(Path path) {
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 16) {
          canvas.drawPath(m.extractPath(d, d + 9), dash);
        }
      }
    }

    final l = lasso;
    if (l != null && l.length > 1) {
      canvas.drawPath(Path()..addPolygon(l, true), Paint()..color = const Color(0x141E8CB4));
      dashed(Path()..addPolygon(l, false));
    }
    final b = bounds;
    if (b != null) {
      final r = b.inflate(10);
      canvas.drawRect(r, Paint()..color = const Color(0x0F1E8CB4));
      dashed(Path()..addRect(r));
    }
  }

  @override
  bool shouldRepaint(_LassoPainter old) => true;
}

/// Acciones para los trazos elegidos con el lazo.
class _StrokeSelectionBar extends StatelessWidget {
  const _StrokeSelectionBar({required this.controller});
  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
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
              Text('${controller.selectedStrokes.length} trazo(s)  ',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              for (final c in fullPalette.take(8))
                GestureDetector(
                  onTap: () => controller.recolorSelection(c),
                  child: Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Más colores',
                icon: const Icon(Icons.palette_outlined),
                onPressed: () async {
                  final c = await pickColor(context);
                  if (c != null) controller.recolorSelection(c);
                },
              ),
              action(Icons.copy_outlined, 'Duplicar', controller.duplicateSelection),
              action(Icons.delete_outline, 'Borrar', controller.deleteSelection),
              action(Icons.check, 'Listo', controller.clearStrokeSelection),
            ],
          ),
        ),
      ),
    );
  }
}
