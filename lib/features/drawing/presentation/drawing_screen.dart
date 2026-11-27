import '../../reader/presentation/doc_chooser.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../application/page_move.dart';
import '../application/handwriting.dart';
import '../data/page_templates.dart';
import 'presentation_screen.dart';
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
import '../../notes/presentation/note_editor_screen.dart' show chooseVideo;
import '../../../core/router.dart' show VideoArgs;
import '../../recording/application/audio_tools.dart' show confirmDeleteRecording;
import '../../../core/screen_capture.dart';
import '../../../core/platform_info.dart';

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
    // El lazo necesita saber cuánto ocupa cada texto.
    DrawingController.itemSizer =
        (it) => it is TextItem ? measureTextItem(it) : DrawingController.roughItemSize(it);
    _load(_path);
    _transform.addListener(_onViewChanged);
  }

  // ------------------------------------- Hojas seguidas (una bajo otra)

  static const _gap = 40.0;
  static const _footerH = 360.0;
  Timer? _viewDebounce;
  bool _twoFingers = false;
  Offset _swipeLast = Offset.zero;
  bool _scrolling = false;
  double _overscroll = 0;

  /// Hojas de la nota (para apilarlas).
  List<DrawingBlock> get _stack => _vertical ? _pages : const [];

  Size _sizeOf(DrawingBlock p) {
    final d = _ctl?.drawing;
    if (p.path == _path && d != null) return Size(d.width, d.height);
    final other = ref.read(drawingFileProvider(p.path)).valueOrNull;
    if (other != null) return Size(other.width, other.height);
    return d == null ? const Size(Drawing.a4Width, Drawing.a4Height) : Size(d.width, d.height);
  }

  /// Distancia desde arriba del montón hasta la hoja [i].
  double _offsetOf(int i) {
    final pages = _stack;
    var y = 0.0;
    for (var k = 0; k < i && k < pages.length; k++) {
      y += _sizeOf(pages[k]).height + _gap;
    }
    return y;
  }

  /// Dónde empieza la hoja activa dentro del montón.
  double get _activeOffset {
    if (!_vertical) return 0;
    final i = _pageIndex;
    return i <= 0 ? 0 : _offsetOf(i);
  }

  double get _stackHeight {
    final pages = _stack;
    return pages.isEmpty ? 0 : _offsetOf(pages.length) - _gap + _footerH;
  }

  /// Al desplazarse, la hoja que queda en el centro de la pantalla pasa a ser
  /// la que se edita.
  void _onViewChanged() {
    if (!_vertical) return;
    _viewDebounce?.cancel();
    _viewDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted || _drawingPointer != null || _editing != null || _viewport == Size.zero) return;
      if (_movingSel || _lassoing || _transferring || _draggingItem) return;
      final pages = _stack;
      if (pages.length < 2) return;
      // Mientras la hoja activa se siga viendo bien, sigue siendo la activa:
      // así "deshacer" actúa en la hoja donde se acaba de escribir y no en
      // la de al lado que quedó en el centro.
      final top = _transform.toScene(Offset.zero).dy;
      final bottom = _transform.toScene(Offset(0, _viewport.height)).dy;
      final i = _pageIndex;
      if (i >= 0) {
        final a = _offsetOf(i), b = a + _sizeOf(pages[i]).height;
        final seen = math.min(b, bottom) - math.max(a, top);
        if (seen >= (bottom - top) * 0.35 || (a >= top && b <= bottom)) return;
      }
      final y = _transform.toScene(Offset(_viewport.width / 2, _viewport.height * 0.45)).dy;
      var target = pages.length - 1;
      for (var i = 0; i < pages.length; i++) {
        if (y < _offsetOf(i) + _sizeOf(pages[i]).height + _gap / 2) {
          target = i;
          break;
        }
      }
      if (pages[target].path != _path) _load(pages[target].path, keepView: true);
    });
  }

  /// Desplazar el montón (un dedo en el fondo gris). Abajo del todo, lo que
  /// sobra cuenta como "tirar para agregar hoja".
  void _scrollBy(double dy) {
    final m = _transform.value;
    final scale = m.getMaxScaleOnAxis();
    final maxTy = 8.0;
    final minTy = math.min(maxTy, _viewport.height - _stackHeight * scale + (_footerH * scale) * 0.35);
    var ty = m.entry(1, 3) + dy;
    if (ty < minTy) {
      _overscroll += minTy - ty;
      ty = minTy;
    } else {
      _overscroll = math.max(0, _overscroll - dy.abs());
    }
    ty = ty.clamp(minTy, maxTy);
    _transform.value = m.clone()..setEntry(1, 3, ty);
    final p = (_overscroll / 140).clamp(0.0, 1.25);
    if ((p - _pull).abs() > 0.02) setState(() => _pull = p);
  }

  /// Rueda del mouse (en la compu): desplaza la hoja hacia arriba y abajo
  /// (con Mayús, de lado). Con Ctrl, acerca o aleja.
  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final ctl = _ctl;
    if (ctl == null || _viewport == Size.zero) return;
    // El touchpad ya mueve la hoja solo cuando se puede mover con la mano.
    if (e.kind == PointerDeviceKind.trackpad && (ctl.mode == InputMode.pan || ctl.stylusOnly)) return;
    final d = ctl.drawing;
    final m = _transform.value;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed) {
      if (e.scrollDelta.dy == 0) return;
      final scale = m.getMaxScaleOnAxis();
      final minScale = d.infinite ? 0.04 : 0.2;
      final next = (scale * math.exp(-e.scrollDelta.dy / 200)).clamp(minScale, 8.0);
      final f = next / scale;
      final p = e.localPosition;
      final zoom = Matrix4.identity()
        ..setEntry(0, 0, f)
        ..setEntry(1, 1, f)
        ..setEntry(0, 3, p.dx * (1 - f))
        ..setEntry(1, 3, p.dy * (1 - f));
      _transform.value = zoom.multiplied(m);
      return;
    }
    var dx = e.scrollDelta.dx, dy = e.scrollDelta.dy;
    if (keys.isShiftPressed && dx == 0) {
      dx = dy;
      dy = 0;
    }
    final scale = m.getMaxScaleOnAxis();
    final margin = d.infinite ? 400.0 : 8.0;
    final pages = _stack;
    final contentH = pages.isEmpty ? d.height + (_vertical ? _footerH * 0.65 : 0) : _stackHeight - _footerH * 0.35;
    double clampT(double t, double content, double view) {
      final min = view - content * scale - margin;
      return min >= margin ? t : t.clamp(min, margin);
    }
    final tx = clampT(m.entry(0, 3) - dx, d.width, _viewport.width);
    final ty = clampT(m.entry(1, 3) - dy, contentH, _viewport.height);
    _transform.value = m.clone()
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  /// Lupa + / − (en la compu): acerca o aleja desde el centro de la vista.
  void _zoomBy(double factor) {
    final ctl = _ctl;
    if (ctl == null || _viewport == Size.zero) return;
    final m = _transform.value;
    final scale = m.getMaxScaleOnAxis();
    final minScale = ctl.drawing.infinite ? 0.04 : 0.2;
    final next = (scale * factor).clamp(minScale, 8.0);
    final f = next / scale;
    final p = Offset(_viewport.width / 2, _viewport.height / 2);
    final zoom = Matrix4.identity()
      ..setEntry(0, 0, f)
      ..setEntry(1, 1, f)
      ..setEntry(0, 3, p.dx * (1 - f))
      ..setEntry(1, 3, p.dy * (1 - f));
    _transform.value = zoom.multiplied(m);
  }

  /// Volver al tamaño normal (la hoja al ancho de la ventana).
  void _zoomFit() => setState(() => _fittedWidth = null);

  Widget _zoomControls(ColorScheme scheme) => Material(
        color: scheme.surface.withValues(alpha: 0.9),
        shape: const StadiumBorder(),
        elevation: 2,
        child: ValueListenableBuilder<Matrix4>(
          valueListenable: _transform,
          builder: (context, m, _) {
            final pct = (m.getMaxScaleOnAxis() / (_fitScale <= 0 ? 1 : _fitScale) * 100).round();
            return Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Alejar (Ctrl −)',
                icon: const Icon(Icons.zoom_out),
                onPressed: () => _zoomBy(1 / 1.25),
              ),
              Tooltip(
                message: 'Tamaño normal (Ctrl 0)',
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _zoomFit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: SizedBox(
                      width: 46,
                      child: Text('$pct %', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Acercar (Ctrl +)',
                icon: const Icon(Icons.zoom_in),
                onPressed: () => _zoomBy(1.25),
              ),
            ]);
          },
        ),
      );

  /// Ir a una hoja del montón (arriba de la pantalla).
  Future<void> _scrollToPage(String path) async {
    await _load(path);
  }

  /// Agregar hoja al final y bajar hasta ella.
  Future<void> _addPageAtEnd() async {
    final pages = _pages;
    if (pages.isEmpty) return;
    if (pages.last.path != _path) await _load(pages.last.path, keepView: true);
    HapticFeedback.mediumImpact();
    await _addPage(copy: false);
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
  bool get _vertical =>
      !(_ctl?.drawing.infinite ?? false) &&
      (ref.read(sharedPreferencesProvider).getString('pages.mode') ?? 'vertical') == 'vertical';

  /// Cuánto se tiró hacia arriba en la última hoja (1 = suelta para agregar).
  double _pull = 0;

  bool get _onLastPage {
    final i = _pageIndex;
    return i >= 0 && i == _pages.length - 1;
  }

  /// ¿El dedo tocó fuera de la hoja (en el fondo gris)? Ahí siempre se puede
  /// tirar o deslizar, aunque se esté dibujando con el dedo.
  /// La portada del cuaderno no se raya: ahí el dedo o el mouse solo
  /// desplazan, como en el fondo gris.
  bool get _onCover => _ctl?.readOnly ?? false;

  /// Por qué no se puede agregar nada aquí (tapa o capa bloqueada).
  void _cantDrawHint(DrawingController ctl) {
    if (ctl.readOnly) {
      _coverHint();
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('La capa activa está oculta o bloqueada')));
  }

  void _coverHint() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('La portada no se puede rayar. Escribe en la hoja siguiente.')));
  }

  bool _outsidePage(Offset global) {
    if (_onCover) return true;
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
    if (_vertical) {
      await _scrollToPage(pages[target].path);
      return;
    }
    _slideDir = dir;
    await _load(pages[target].path);
    if (mounted) _slide.forward(from: 0);
  }

  void _swipeDown(PointerDownEvent e) {
    _swipeFingers++;
    // Con dos dedos se mueve la vista (también en el modo de dibujar).
    if (_swipeFingers >= 2 && !_twoFingers) setState(() => _twoFingers = true);
    _swipeLast = e.position;
    // (En modo mano o "solo lápiz" ya mueve la vista el visor: no doble.)
    final viewerPans = _ctl != null && (_ctl!.mode == InputMode.pan || _ctl!.stylusOnly);
    _scrolling =
        _vertical && !viewerPans && _swipeFingers == 1 && _outsidePage(e.position) && _editing == null;
    _overscroll = 0;
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
    if (_vertical) {
      // Un dedo en el fondo gris (o en modo mano): bajar y subir por las hojas.
      if (_scrolling) {
        if (_swipeFingers == 1) _scrollBy(e.position.dy - _swipeLast.dy);
        _swipeLast = e.position;
      }
      return;
    }
  }

  Future<void> _swipeUp(PointerEvent e) async {
    _swipeFingers = (_swipeFingers - 1).clamp(0, 10);
    if (_swipeFingers < 2 && _twoFingers) setState(() => _twoFingers = false);
    if (_vertical) {
      final pulled = _pull;
      _scrolling = false;
      _swipePointer = null;
      _overscroll = 0;
      if (_pull != 0) setState(() => _pull = 0);
      if (pulled >= 1) await _addPageAtEnd();
      return;
    }
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

  /// Deshacer de cada hoja, para no perderlo al pasar de hoja y volver.
  final _histories = <String, (List<Drawing>, List<Drawing>, Drawing)>{};

  /// Cambios de hoja, uno por vez: si se piden dos seguidos (por ejemplo,
  /// dos dedos que tocan otra hoja), se mezclaban y el deshacer o la vista
  /// previa de una hoja quedaban con los de otra.
  Future<void> _loadChain = Future.value();
  String? _wanted;

  Future<void> _load(String path, {bool keepView = false}) {
    _wanted = path;
    final f = _loadChain.then((_) => _doLoad(path, keepView: keepView));
    _loadChain = f.catchError((Object _) {});
    return f;
  }

  Future<void> _doLoad(String path, {required bool keepView}) async {
    // Ya se pidió otra hoja después de esta, o ya es la activa.
    if (!mounted || _wanted != path) return;
    if (_ctl != null && path == _path) return;
    if (_editing != null) _commitEditing();
    final old = _ctl;
    final oldPath = _path;
    if (old != null) {
      await old.flush();
      ref.invalidate(drawingFileProvider(oldPath));
      unawaited(_indexHandwriting(oldPath, old.drawing));
      _histories[oldPath] = old.history;
    }
    final store = ref.read(drawingStoreProvider);
    final drawing = await store.load(path);
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    final keepTool = old?.tool;
    setState(() {
      _path = path;
      // Volver a ajustar la hoja a la pantalla (salvo al seguir bajando por
      // las hojas seguidas: ahí la vista queda donde está).
      if (!keepView) _fittedWidth = null;
      _ctl = DrawingController(drawing, onSave: (d) => store.save(path, d))
        ..stylusOnly = old?.stylusOnly ?? settings.stylusOnly;
      if (keepTool != null) _ctl!.selectTool(keepTool);
      // Mantener también "borrar trazo completo" (o lazo, texto…) en la hoja nueva.
      final keepMode = old?.mode;
      if (keepMode != null && keepMode != InputMode.draw) _ctl!.selectMode(keepMode);
      final h = _histories[path];
      if (h != null) _ctl!.restoreHistory(h);
    });
    if (old != null) {
      // Por si se alcanzó a escribir algo mientras se abría la otra hoja.
      final wasDirty = old.isDirty;
      await old.flush();
      if (wasDirty && mounted) {
        _histories[oldPath] = old.history;
        ref.invalidate(drawingFileProvider(oldPath));
      }
      old.dispose();
    }
  }

  @override
  void dispose() {
    _viewDebounce?.cancel();
    _transform.removeListener(_onViewChanged);
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
    final c = _ctl;
    if (c != null) unawaited(_indexHandwriting(_path, c.drawing));
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------- Páginas

  List<DrawingBlock> get _pages => (ref.read(blocksProvider(widget.noteId)).valueOrNull ??
          const <NoteBlock>[])
      .whereType<DrawingBlock>()
      .toList();

  int get _pageIndex => _pages.indexWhere((p) => p.path == _path);



  Future<void> _addPage({required bool copy, Drawing? from}) async {
    final ctl = _ctl;
    final pages = _pages;
    final i = _pageIndex;
    if (ctl == null || i < 0) return;
    await ctl.flush();
    final storage = ref.read(fileStorageProvider);
    final path = await storage.newDrawingPath();
    final d = ctl.drawing;
    final newDrawing = from ??
        (copy
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
          ));
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

  /// Dónde se tocó la portada (para avisar que no se raya).
  Offset? _coverTap;

  void _onDown(PointerDownEvent e) {
    final ctl = _ctl!;
    _pointers.add(e.pointer);
    if (ctl.mode == InputMode.text || ctl.mode == InputMode.select) {
      _tapStart = _pointers.length == 1 ? e.localPosition : null;
      // Lazo: en "Seleccionar", tocar fuera de textos/fotos dibuja el lazo
      // o, si se toca dentro de lo ya seleccionado, lo mueve.
      if (ctl.mode == InputMode.select && !_pointerOnItem && !_onCover) {
        if (_pointers.length > 1) {
          ctl.cancelLasso();
          _lassoing = false;
          _movingSel = false;
          return;
        }
        // Capa con candado u oculta: el lazo no la toca (avisar).
        if (!ctl.canDrawOnActiveLayer) {
          if (_pointers.length == 1) _cantDrawHint(ctl);
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
    if (_onCover) {
      // Arrastrar para desplazarse no es un intento de escribir: avisar
      // solo con un toque.
      _coverTap = e.localPosition;
      return;
    }
    // El borrador funciona en todas las capas sin candado.
    final erasing = ctl.mode == InputMode.eraseStrokes || ctl.tool == ToolType.eraser;
    if (!erasing && !ctl.canDrawOnActiveLayer) {
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
      final wasMoving = _movingSel;
      _lassoing = false;
      _movingSel = false;
      _moveLast = null;
      _tapStart = null;
      _pointerOnItem = false;
      if (wasMoving) {
        setState(() {}); // volver a recortar en el borde de la hoja
        unawaited(_moveSelectionToNeighbor());
      }
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
        _onCover ? _coverHint() : _newText(e.localPosition);
      }
      return;
    }
    final tap = _coverTap;
    _coverTap = null;
    if (tap != null && (e.localPosition - tap).distance < 12 && _onCover) _coverHint();
    if (e.pointer != _drawingPointer) return;
    _drawingPointer = null;
    _ctl!.endStroke();
  }

  void _onCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    _disarmHold();
    if (_lassoing || _movingSel) {
      // Android cortó el toque (un aviso, una llamada): soltar el lazo para
      // que no quede trabado.
      if (_lassoing) _ctl?.cancelLasso();
      final wasMoving = _movingSel;
      _lassoing = false;
      _movingSel = false;
      _moveLast = null;
      _tapStart = null;
      if (wasMoving) setState(() {});
    }
    if (e.pointer == _drawingPointer) {
      _drawingPointer = null;
      _ctl!.cancelStroke();
    }
  }

  /// Si lo elegido con el lazo se soltó más allá del borde de abajo (o de
  /// arriba) de la hoja, pasa a la hoja siguiente (o anterior), en el mismo
  /// lugar donde se soltó. Al final del cuaderno se agrega una hoja nueva.
  Future<void> _moveSelectionToNeighbor() async {
    final ctl = _ctl;
    final b = ctl?.selectionBounds;
    if (ctl == null || b == null) return;
    final d = ctl.drawing;
    if (d.infinite) return;
    final dir = b.center.dy > d.height ? 1 : (b.center.dy < 0 ? -1 : 0);
    if (dir == 0) return;
    final pages = _pages;
    final i = _pageIndex;
    if (i < 0) return;
    final fromPath = _path;
    final t = i + dir;
    // No hay hoja antes (o es la tapa): devolverlo dentro de la hoja.
    void keepInside() {
      final fix = _fitInside(b, d);
      if (fix != Offset.zero) ctl.moveSelection(fix);
    }

    if (t < 0) {
      keepInside();
      return;
    }
    final store = ref.read(drawingStoreProvider);
    _viewDebounce?.cancel();
    _transferring = true;
    try {
      if (t >= pages.length) {
        // Más abajo de la última hoja: agregar una nueva y pasar ahí.
        final (strokes, items) = ctl.takeSelection(afterDrag: true);
        await _addPage(copy: false);
        final c = _ctl!;
        final (s2, i2) = _shift(strokes, items, Offset(0, -(d.height + _gap)), c.drawing);
        if (identical(c, ctl)) {
          // No se pudo crear la hoja: devolverlo donde estaba.
          ctl.undo();
          return;
        }
        final before = c.drawing;
        c.addContent(s2, i2);
        _linkMove(fromPath, c, before);
        _afterMove();
        return;
      }
      final targetPath = pages[t].path;
      final target = await store.load(targetPath);
      if (target.paper.template == PaperTemplate.cover) {
        keepInside();
        _coverHint();
        return;
      }
      final dy = dir > 0 ? -(d.height + _gap) : target.height + _gap;
      final (strokes, items) = ctl.takeSelection(afterDrag: true);
      final (s2, i2) = _shift(strokes, items, Offset(0, dy), target);
      await _load(targetPath, keepView: _vertical);
      final c = _ctl;
      if (_path == targetPath && c != null && !identical(c, ctl)) {
        final before = c.drawing;
        c.addContent(s2, i2);
        _linkMove(fromPath, c, before);
        _afterMove();
      } else {
        // Se abrió otra hoja mientras tanto: se guarda directo en el archivo.
        final fresh = await store.load(targetPath);
        final layers = [...fresh.layers];
        final li = layers.lastIndexWhere((l) => l.visible && !l.locked);
        final k = li < 0 ? layers.length - 1 : li;
        layers[k] = layers[k].copyWith(
            strokes: [...layers[k].strokes, ...s2], items: [...layers[k].items, ...i2]);
        await store.save(targetPath, fresh.copyWith(layers: layers));
        _histories.remove(targetPath);
        if (mounted) ref.invalidate(drawingFileProvider(targetPath));
      }
    } finally {
      _transferring = false;
    }
  }

  bool _transferring = false;

  /// Lo último que se pasó a otra hoja (para deshacerlo en las dos).
  PageMove? _move;
  PageMove? _movedBack;

  void _linkMove(String from, DrawingController to, Drawing before) {
    if (identical(to.drawing, before)) return; // no se agregó nada
    _move = PageMove(from: from, to: _path, after: to.drawing, before: before);
    _movedBack = null;
  }

  /// Deshacer: si lo último fue recibir algo de otra hoja, también se
  /// devuelve a esa hoja (si no, desaparecía de las dos).
  void _undo(DrawingController c) {
    final m = _move;
    if (m != null && _path == m.to && identical(c.drawing, m.after)) {
      c.undo();
      _move = null;
      if (identical(c.drawing, m.before)) _movedBack = m;
      unawaited(_stepClosedPage(m.from, undo: true));
      return;
    }
    c.undo();
  }

  void _redo(DrawingController c) {
    final m = _movedBack;
    if (m != null && _path == m.to && identical(c.drawing, m.before)) {
      c.redo();
      _movedBack = null;
      if (identical(c.drawing, m.after)) _move = m;
      unawaited(_stepClosedPage(m.from, undo: false));
      return;
    }
    c.redo();
  }

  /// Deshace o rehace un paso en una hoja que no está abierta.
  Future<void> _stepClosedPage(String path, {required bool undo}) async {
    final h = _histories[path];
    if (h == null || path == _path) return;
    final step = undo ? undoClosedPage(h) : redoClosedPage(h);
    if (step == null) return;
    final (drawing, history) = step;
    await ref.read(drawingStoreProvider).save(path, drawing);
    _histories[path] = history;
    if (mounted) ref.invalidate(drawingFileProvider(path));
  }

  /// Cuánto hay que correr [r] para que quede dentro de la hoja [d].
  static Offset _fitInside(Rect r, Drawing d) {
    double fit(double lo, double hi, double max) {
      if (hi - lo >= max) return -lo + (max - (hi - lo)) / 2;
      if (lo < 0) return -lo;
      if (hi > max) return max - hi;
      return 0;
    }

    return Offset(fit(r.left, r.right, d.width), fit(r.top, r.bottom, d.height));
  }

  /// Se está arrastrando un texto, foto, sticker o figura.
  bool _draggingItem = false;

  /// Mientras se arrastra algo, lo que sale de la hoja se sigue viendo.
  bool get _unclipped => _movingSel || _draggingItem;

  void _itemMoveEnded(String id) {
    if (!_draggingItem) return;
    _draggingItem = false;
    final ctl = _ctl;
    final it = ctl?.findItem(id)?.$2;
    if (ctl == null || it == null) {
      setState(() {});
      return;
    }
    final d = ctl.drawing;
    if (!d.infinite && (it.y > d.height || it.y < 0)) {
      ctl.selectForMove(id);
      unawaited(_moveSelectionToNeighbor());
    } else {
      setState(() {});
    }
  }

  void _afterMove() {
    final c = _ctl;
    if (c == null) return;
    if (c.mode != InputMode.select) c.selectMode(InputMode.select);
    HapticFeedback.selectionClick();
  }

  /// Corre los trazos y elementos [delta] y, si aun así quedan fuera de
  /// la hoja [to], los mete adentro.
  (List<Stroke>, List<CanvasItem>) _shift(
      List<Stroke> strokes, List<CanvasItem> items, Offset delta, Drawing to) {
    Rect? r;
    for (final s in strokes) {
      final b = s.bounds.shift(delta);
      r = r == null ? b : r.expandToInclude(b);
    }
    for (final it in items) {
      final b = DrawingController.itemRect(it).shift(delta);
      r = r == null ? b : r.expandToInclude(b);
    }
    final total = delta + (r == null ? Offset.zero : _fitInside(r, to));
    return (
      [for (final s in strokes) DrawingController.shiftedStroke(s, total)],
      [for (final it in items) it.moved(x: it.x + total.dx, y: it.y + total.dy)],
    );
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
      child: CallbackShortcuts(
        bindings: ctl == null ? const {} : _shortcuts(ctl),
        child: Focus(
          autofocus: true,
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
                                final off = _vertical ? 0.0 : _slideDir * (1 - v) * 140;
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
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.grid_view_outlined, size: 16, color: Colors.black54),
                                    const SizedBox(width: 6),
                                    Text(
                                      index < 0 ? '–' : 'Hoja ${index + 1} de ${pages.length}',
                                      style: const TextStyle(fontSize: 15, color: Colors.black54),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Lupa + / − (solo en la compu).
                        if (isDesktop)
                          Positioned(left: 12, bottom: 10, child: _zoomControls(scheme)),
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
                        ? _StrokeSelectionBar(controller: ctl, onToText: _strokesToText)
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
        ),
      ),
    );
  }

  Widget _icon(IconData icon, String tooltip, VoidCallback? onTap,
      {bool selected = false, Widget? glyph, VoidCallback? onLongPress}) {
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
        icon: glyph ?? Icon(icon, size: 24),
        onPressed: onTap,
        onLongPress: onLongPress,
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
          _icon(Icons.grid_view_outlined, 'Ver todas las hojas', _showThumbnails),
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
      isDesktop
          ? (Icons.screenshot_monitor_outlined, 'Imagen o recorte', 'photo')
          : (Icons.photo_camera_outlined, 'Foto', 'photo'),
      (Icons.mic_none, recording ? 'Grabando…' : 'Grabar audio', 'rec'),
      (Icons.ondemand_video_outlined, 'Video y notas', 'video'),
      (Icons.slideshow_outlined, 'PDF o diapositivas', 'doc'),
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
      case 'video':
        final source = await chooseVideo(context, ref);
        if (source != null && mounted) {
          await ctl.flush();
          if (!mounted) return;
          context.push('/notes/${widget.noteId}/video', extra: VideoArgs(videoPath: source, startMs: 0));
        }
      case 'doc':
        final doc = await chooseDocument(context, ref, noteId: widget.noteId);
        if (doc != null && mounted) {
          await ctl.flush();
          if (!mounted) return;
          context.push('/notes/${widget.noteId}/doc', extra: doc);
        }
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
        await _newPageChooser();
    }
  }

  /// "Hoja nueva": igual que esta, o desde una plantilla propia.
  Future<void> _newPageChooser() async {
    final templates = await PageTemplates.list();
    if (!mounted) return;
    final pick = await showModalBottomSheet<Object>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('Hoja nueva', style: TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('En blanco, con la misma hoja'),
              onTap: () => Navigator.pop(context, 'same'),
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('Lienzo infinito'),
              subtitle: const Text('Crece solo mientras dibujas: mapas mentales, esquemas…'),
              onTap: () => Navigator.pop(context, 'infinite'),
            ),
            if (templates.isNotEmpty) const Divider(),
            if (templates.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(alignment: Alignment.centerLeft, child: Text('Mis plantillas')),
            ),
            for (final t in templates)
              ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: Text(t.name),
                onTap: () => Navigator.pop(context, t),
                trailing: IconButton(
                  tooltip: 'Borrar plantilla',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await PageTemplates.delete(t);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ),
          ]),
        ),
      ),
    );
    if (pick == 'same') {
      await _addPage(copy: false);
    } else if (pick == 'infinite') {
      final paper = _ctl?.drawing.paper ?? const PaperStyle();
      await _addPage(
        copy: false,
        from: Drawing.blank(paper: paper).copyWith(
          infinite: true,
          width: Drawing.infiniteStart,
          height: Drawing.infiniteStart,
        ),
      );
      // Elegir enseguida hacia dónde crece y el tipo de papel.
      final c = _ctl;
      if (mounted && c != null) {
        _sheet(PaperSheet(
          controller: c,
          onPickImage: ref.read(cameraServiceProvider).pickImageFromGallery,
        ));
      }
    } else if (pick is PageTemplate) {
      final d = await PageTemplates.load(pick);
      await _addPage(copy: false, from: d);
    }
  }

  Future<void> _saveAsTemplate(DrawingController ctl) async {
    await ctl.flush();
    if (!mounted) return;
    final name = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guardar como plantilla'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('La hoja se guarda tal como está (dibujos, stickers, tablas). '
              'Luego, en Insertar → Hoja nueva, la eliges para empezar otra igual.'),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Planner semanal, Ejercicios…'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, name.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (r == null || r.trim().isEmpty) return;
    await PageTemplates.save(r, ctl.drawing);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Plantilla "${r.trim()}" guardada ✓')));
    }
  }

  /// Tocar una herramienta la elige; tocarla otra vez la apaga y el dedo
  /// solo mueve la hoja (así no se raya sin querer). Sus ajustes (color,
  /// grosor…) se abren dejándola apretada.
  void _tapTool(DrawingController c, ToolType tool, {required bool on}) {
    _closePanel();
    if (!on) {
      c.selectTool(tool);
      return;
    }
    c.selectMode(InputMode.pan);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        duration: Duration(seconds: 3),
        content: Text('Herramienta apagada: el dedo solo mueve la hoja. '
            'Para cambiar color o grosor, deja apretada la herramienta.'),
      ));
  }

  void _toolSettings(DrawingController c, ToolType tool, ToolPanel panel) {
    HapticFeedback.selectionClick();
    final on = c.tool == tool &&
        (c.mode == InputMode.draw || (tool == ToolType.eraser && c.mode == InputMode.eraseStrokes));
    if (!on) c.selectTool(tool);
    if (_panel != panel) _togglePanel(panel);
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
                _icon(Icons.undo, 'Deshacer', c.canUndo ? () => _undo(c) : null),
                _icon(Icons.redo, 'Rehacer', c.canRedo ? () => _redo(c) : null),
                const SizedBox(height: 30, child: VerticalDivider(width: 10)),
                _icon(toolIcon(_pen), _pen.label, () => _tapTool(c, _pen, on: penOn),
                    onLongPress: () => _toolSettings(c, _pen, ToolPanel.pen), selected: penOn),
                _icon(Icons.highlight, 'Resaltador', glyph: const HighlighterIcon(), () => _tapTool(c, ToolType.highlighter, on: hlOn),
                    onLongPress: () => _toolSettings(c, ToolType.highlighter, ToolPanel.highlighter), selected: hlOn),
                _icon(Icons.linear_scale, 'Cinta washi', glyph: const TapeIcon(), () => _tapTool(c, ToolType.tape, on: tapeOn),
                    onLongPress: () => _toolSettings(c, ToolType.tape, ToolPanel.tape), selected: tapeOn),
                _icon(Icons.auto_fix_normal, 'Borrador', glyph: const EraserIcon(), () => _tapTool(c, ToolType.eraser, on: eraserOn),
                    onLongPress: () => _toolSettings(c, ToolType.eraser, ToolPanel.eraser), selected: eraserOn),
                _icon(Icons.highlight_alt, 'Lazo: rodea trazos para moverlos o pasarlos a texto; toca textos y fotos para editarlos', glyph: const LassoIcon(), () {
                  final first = c.mode != InputMode.select;
                  c.selectMode(InputMode.select);
                  _closePanel();
                  if (first) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(
                        duration: Duration(seconds: 2),
                        content: Text('Lazo: rodea con el dedo lo que quieras mover, copiar o pasar a texto'),
                      ));
                  }
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
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: const Text('Guardar como plantilla'),
              subtitle: const Text('Para empezar otras hojas iguales'),
              onTap: () => Navigator.pop(context, 'template'),
            ),
            ListTile(
              leading: const Icon(Icons.co_present_outlined),
              title: const Text('Presentar (con puntero láser)'),
              onTap: () => Navigator.pop(context, 'present'),
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
      case 'template':
        await _saveAsTemplate(ctl);
      case 'present':
        await ctl.flush();
        if (!mounted) return;
        final i = _pageIndex;
        await Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => PresentationScreen(
            paths: [for (final p in _pages) p.path],
            initial: i < 0 ? 0 : i,
          ),
        ));
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

  // ------------------------------------------------- Atajos de teclado

  /// Atajos para la compu (o una tablet con teclado). No se usan mientras
  /// se escribe un texto.
  Map<ShortcutActivator, VoidCallback> _shortcuts(DrawingController c) {
    bool typing() =>
        _editing != null ||
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    VoidCallback guard(VoidCallback f) => () {
          if (!typing()) f();
        };
    void tool(ToolType t) {
      c.selectTool(t);
      _closePanel();
    }

    return {
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): guard(() => _undo(c)),
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): guard(() => _undo(c)),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): guard(() => _redo(c)),
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): guard(() => _redo(c)),
      const SingleActivator(LogicalKeyboardKey.keyP): guard(() => tool(ToolType.pen)),
      const SingleActivator(LogicalKeyboardKey.keyB): guard(() => tool(ToolType.pen)),
      const SingleActivator(LogicalKeyboardKey.keyH): guard(() => tool(ToolType.highlighter)),
      const SingleActivator(LogicalKeyboardKey.keyE): guard(() => tool(ToolType.eraser)),
      const SingleActivator(LogicalKeyboardKey.keyL): guard(() {
        c.selectMode(InputMode.select);
        _closePanel();
      }),
      const SingleActivator(LogicalKeyboardKey.keyT): guard(() {
        c.selectMode(InputMode.text);
        _closePanel();
      }),
      const SingleActivator(LogicalKeyboardKey.delete): guard(c.deleteSelection),
      const SingleActivator(LogicalKeyboardKey.backspace): guard(c.deleteSelection),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): guard(c.duplicateSelection),
      const SingleActivator(LogicalKeyboardKey.escape): guard(c.clearStrokeSelection),
      const SingleActivator(LogicalKeyboardKey.equal, control: true): guard(() => _zoomBy(1.25)),
      const SingleActivator(LogicalKeyboardKey.add, control: true): guard(() => _zoomBy(1.25)),
      const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): guard(() => _zoomBy(1.25)),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): guard(() => _zoomBy(1 / 1.25)),
      const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): guard(() => _zoomBy(1 / 1.25)),
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): guard(_zoomFit),
      const SingleActivator(LogicalKeyboardKey.pageDown): guard(() => _turn(1)),
      const SingleActivator(LogicalKeyboardKey.pageUp): guard(() => _turn(-1)),
    };
  }

  // ----------------------------------------------------- Letra a mano

  /// Guarda el texto reconocido de la hoja para que la búsqueda encuentre
  /// lo escrito a mano (solo si el reconocedor ya está bajado).
  Future<void> _indexHandwriting(String path, Drawing d) async {
    try {
      // Leer todo de ref antes de esperar: la pantalla puede cerrarse.
      final prefs = ref.read(sharedPreferencesProvider);
      final repo = ref.read(notesRepositoryProvider);
      final block = _pages.where((p) => p.path == path).firstOrNull;
      if (block == null || prefs.getBool('hw.enabled') == false) return;
      final hw = Handwriting.instance;
      if (!await hw.isReady()) return;
      final strokes = [for (final l in d.layers) ...l.strokes];
      final key = 'hw.count.$path';
      if (prefs.getInt(key) == strokes.length) return; // sin cambios
      final text = await hw.recognize(strokes);
      await repo.updateText(block.id, text.isEmpty ? '' : '✍️ $text');
      await prefs.setInt(key, strokes.length);
    } catch (_) {}
  }

  /// Lazo → "A texto": lo escrito a mano se vuelve texto.
  Future<void> _strokesToText() async {
    final ctl = _ctl;
    if (ctl == null || !ctl.hasStrokeSelection) return;
    final strokes = [
      for (final i in ctl.selectedStrokes)
        if (i < ctl.activeLayer.strokes.length) ctl.activeLayer.strokes[i],
    ];
    final bounds = ctl.selectionBounds;
    final status = ValueNotifier<String>('Leyendo tu letra…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: ValueListenableBuilder(valueListenable: status, builder: (_, v, __) => Text(v))),
        ]),
      ),
    );
    String text;
    try {
      if (!await Handwriting.instance.isReady()) {
        status.value = 'Bajando el lector de letra (solo la primera vez)…';
      }
      text = await Handwriting.instance.recognize(strokes);
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    final edit = TextEditingController(text: text);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tu letra en texto'),
        content: TextField(
          controller: edit,
          maxLines: 8,
          minLines: 2,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            helperText: 'Corrige lo que haya leído mal',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'copy'), child: const Text('Copiar')),
          TextButton(onPressed: () => Navigator.pop(context, 'add'), child: const Text('Poner al lado')),
          FilledButton(onPressed: () => Navigator.pop(context, 'replace'), child: const Text('Cambiar por texto')),
        ],
      ),
    );
    if (action == null || !mounted || edit.text.trim().isEmpty) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: edit.text.trim()));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Texto copiado ✓')));
      return;
    }
    final b = bounds ?? Rect.fromLTWH(100, 100, 400, 100);
    final base = _lastTextStyle;
    final item = TextItem(
      id: DrawingController.newItemId(),
      x: 0,
      y: 0,
      text: edit.text.trim(),
      font: base?.font ?? 'Patrick Hand',
      size: base?.size ?? 34,
      color: base?.color ?? 0xFF1F2328,
      width: math.max(240, b.width + 40),
    );
    final size = measureTextItem(item);
    final placed = item.copyWith(
      x: (action == 'replace' ? b.left : b.right + 20) + size.width / 2,
      y: b.top + size.height / 2,
    );
    if (action == 'replace') ctl.deleteSelection();
    ctl.clearStrokeSelection();
    _placeAndSelect(placed);
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
                      : IconButton(
                          tooltip: 'Borrar grabación',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (await confirmDeleteRecording(context, ref, b) && context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                        ),
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
      _cantDrawHint(ctl);
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

  bool get _fitDuringBuild => SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks;

  Widget _canvas(DrawingController ctl) {
    return LayoutBuilder(
      builder: (context, c) {
        return ListenableBuilder(
          listenable: ctl,
          builder: (context, _) {
            final d = ctl.drawing;
            // Ajustar la hoja al ancho de la pantalla la primera vez (y al
            // girarla entre vertical/horizontal).
            // El lienzo infinito crece: se ajusta a 1000 de ancho y no se
            // vuelve a ajustar cuando crece.
            final fitW = d.infinite ? Drawing.a4Width : d.width;
            final fitKey = c.maxWidth * 10000 + fitW + (d.infinite ? 0.5 : 0);
            if (_fittedWidth != fitKey) {
              _fittedWidth = fitKey;
              final scale = (c.maxWidth - 16) / fitW;
              _fitScale = scale;
              final m = Matrix4.identity()
                ..setEntry(0, 0, scale)
                ..setEntry(1, 1, scale)
                ..setEntry(0, 3, 8)
                // Con hojas seguidas: la hoja activa arriba de la pantalla.
                ..setEntry(1, 3, 8 - _activeOffset * scale);
              // Si la hoja cambia de tamaño mientras se dibuja la pantalla
              // (por ejemplo al mover la raya en "PDF y notas"), se ajusta
              // justo después: no se puede avisar en medio del dibujo.
              if (_fitDuringBuild) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _transform.value = m;
                });
              } else {
                _transform.value = m;
              }
            }
            _viewport = Size(c.maxWidth, c.maxHeight);
            return Listener(
              onPointerSignal: _onWheel,
              child: InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              // La rueda del mouse desplaza la hoja (ver _onWheel), no la agranda.
              scaleFactor: 1e12,
              minScale: d.infinite ? 0.04 : 0.2,
              maxScale: 8,
              boundaryMargin: EdgeInsets.all(d.infinite ? 1200 : 400),
              panEnabled: ctl.mode == InputMode.pan || ctl.stylusOnly || _twoFingers,
              child: _stacked(ctl, Container(
                key: _pageKey,
                width: d.width,
                height: d.height,
                // Con varias hojas a la vista, un borde suave marca la hoja
                // activa: ahí actúan deshacer, rehacer y lo que se inserta.
                foregroundDecoration: _stack.length > 1
                    ? BoxDecoration(border: Border.all(color: const Color(0x661E8CB4), width: 3))
                    : null,
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
                      // Cada capa: sus fotos, textos y stickers, y ENCIMA sus
                      // trazos (así se puede dibujar y resaltar sobre una foto).
                      for (var i = 0; i < d.layers.length; i++)
                        if (d.layers[i].visible) ...[
                          if (d.layers[i].items.isNotEmpty)
                            Opacity(
                              opacity: d.layers[i].opacity,
                              child: IgnorePointer(
                                // Los elementos solo se tocan con "Texto" o "Mover".
                                // Con algo elegido por el lazo, se mueve todo junto.
                                ignoring: !(ctl.mode == InputMode.select ||
                                        ctl.mode == InputMode.text) ||
                                    d.layers[i].locked ||
                                    ctl.hasStrokeSelection,
                                child: Stack(
                                  clipBehavior: _unclipped ? Clip.none : Clip.hardEdge,
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
                                        onMoveStart: () => _draggingItem = true,
                                        onMoveEnd: _itemMoveEnded,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          // Los trazos no tapan los toques a fotos y textos.
                          IgnorePointer(
                            child: RepaintBoundary(
                              child: CustomPaint(painter: LayerPainter(ctl, i, clip: !_unclipped)),
                            ),
                          ),
                        ],
                      if (ctl.lasso != null || ctl.hasStrokeSelection)
                        IgnorePointer(child: CustomPaint(painter: _LassoPainter(ctl.lasso, ctl.selectionBounds))),
                      if (_editing != null) _editingField(_editing!),
                    ],
                  ),
                ),
              )),
              ),
            );
          },
        );
      },
    );
  }

  /// En modo "tirar", la hoja activa va entre las demás hojas (que se ven
  /// sin editar; al tocar una o llegar a ella, pasa a ser la activa), y al
  /// final el aviso para agregar otra.
  Widget _stacked(DrawingController ctl, Widget active) {
    if (!_vertical) return active;
    final pages = (ref.watch(blocksProvider(widget.noteId)).valueOrNull ?? const <NoteBlock>[])
        .whereType<DrawingBlock>()
        .toList();
    final i = pages.indexWhere((p) => p.path == _path);
    if (pages.length < 2 || i < 0) {
      return Column(mainAxisSize: MainAxisSize.min, children: [active, _footer(ctl.drawing.width)]);
    }
    final fallback = Size(ctl.drawing.width, ctl.drawing.height);
    // Las hojas van una bajo otra, pero la activa se pinta al final (encima):
    // así lo que se arrastra con el lazo hacia la hoja de abajo o de arriba
    // se sigue viendo mientras se mueve.
    final sizes = [for (final p in pages) _sizeOf(p)];
    final width = sizes.fold<double>(ctl.drawing.width, (w, s) => math.max(w, s.width));
    final tops = <double>[];
    var y = 0.0;
    for (final s in sizes) {
      tops.add(y);
      y += s.height + _gap;
    }
    final footerTop = y - _gap;
    Widget at(int k, Widget child) => Positioned(
          key: ValueKey('page-${pages[k].path}'),
          top: tops[k],
          left: (width - sizes[k].width) / 2,
          width: sizes[k].width,
          height: sizes[k].height,
          child: child,
        );
    return SizedBox(
      width: width,
      height: footerTop + _footerH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (k, p) in pages.indexed)
            if (k != i)
              at(
                k,
                _StaticPage(
                  key: ValueKey(p.path),
                  path: p.path,
                  fallback: fallback,
                  detailed: (k - i).abs() <= 3,
                  onTap: () => _load(p.path, keepView: true),
                ),
              ),
          Positioned(
            top: footerTop,
            left: (width - ctl.drawing.width) / 2,
            child: _footer(ctl.drawing.width),
          ),
          at(i, active),
        ],
      ),
    );
  }

  /// Debajo de la última hoja: "Tira hacia arriba para agregar una página".
  Widget _footer(double width) {
    final ready = _pull >= 1;
    final color = ready ? const Color(0xFF1E8CB4) : const Color(0xFF8A8F98);
    return SizedBox(
      width: width,
      height: _footerH,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.translate(
            offset: Offset(0, -24 * _pull),
            child: Icon(Icons.arrow_upward_rounded, size: 56 + 16 * _pull, color: color),
          ),
          Icon(Icons.note_add, size: 90, color: color),
          const SizedBox(height: 12),
          Text(ready ? 'Suelta para agregar la página' : 'Tira hacia arriba para agregar una página',
              style: TextStyle(fontSize: 34, color: color)),
          const SizedBox(height: 16),
          TextButton.icon(
            style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 30)),
            onPressed: _addPageAtEnd,
            icon: const Icon(Icons.add, size: 36),
            label: const Text('o toca aquí'),
          ),
        ],
      ),
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
    final p = MatrixUtils.transformPoint(m, _editTopLeft + Offset(0, _activeOffset));
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
    final p = _transform.toScene(_viewport.center(Offset.zero)) - Offset(0, _activeOffset);
    return Offset(p.dx.clamp(0, d.width).toDouble(), p.dy.clamp(0, d.height).toDouble());
  }

  Future<void> _addImage({required bool camera, String? fromPath}) async {
    final ctl = _ctl!;
    if (!ctl.canDrawOnActiveLayer) {
      _cantDrawHint(ctl);
      return;
    }
    final path = fromPath ?? await pickAndCropImage(context, ref, camera: camera, forNoteId: widget.noteId);
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

  /// Compu: recortar un pedazo de la pantalla (un video, una página web,
  /// una diapositiva) con la herramienta de capturas del sistema.
  Future<void> _screenClip() async {
    try {
      final shot = await captureScreenRegion();
      if (shot == null || !mounted) return;
      final saved = await ref.read(fileStorageProvider).importFile(shot, folder: 'images');
      await _addImage(camera: false, fromPath: saved);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _chooseImageSource() async {
    if (isDesktop) {
      final clip = await showModalBottomSheet<bool>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.screenshot_monitor_outlined),
              title: const Text('Recorte de pantalla'),
              subtitle: const Text('Eliges con el mouse un pedazo de la pantalla: un video, una web, diapositivas…'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Elegir una imagen'),
              onTap: () => Navigator.pop(context, false),
            ),
          ]),
        ),
      );
      if (clip == true) await _screenClip();
      if (clip == false) await _addImage(camera: false);
      return;
    }
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
  const _StrokeSelectionBar({required this.controller, required this.onToText});
  final DrawingController controller;
  final VoidCallback onToText;

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
              if (controller.selectedStrokes.isNotEmpty) action(Icons.text_fields, 'A texto', onToText),
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

/// Una hoja del montón que no se está editando: se ve igual, y al tocarla
/// pasa a ser la activa.
class _StaticPage extends ConsumerWidget {
  const _StaticPage({
    super.key,
    required this.path,
    required this.fallback,
    required this.detailed,
    required this.onTap,
  });

  final String path;
  final Size fallback;

  /// Lejos de la hoja activa solo se dibuja el papel (más liviano).
  final bool detailed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(drawingFileProvider(path)).valueOrNull;
    final w = d?.width ?? fallback.width, h = d?.height ?? fallback.height;
    // Basta con apoyar el dedo (o el lápiz) para que la hoja pase a ser la
    // que se edita; antes había que dar un toque limpio, y al arrastrar el
    // borrador sobre otra hoja no pasaba nada.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onTap(),
      child: Container(
        width: w,
        height: h,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black26)],
        ),
        child: d == null
            ? null
            : Stack(
                fit: StackFit.expand,
                children: [
                  PaperView(paper: d.paper),
                  if (detailed) DrawingLayersStaticView(drawing: d, painterFor: StaticLayerPainter.new),
                ],
              ),
      ),
    );
  }
}
