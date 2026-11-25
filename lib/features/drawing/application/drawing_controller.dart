import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../domain/drawing.dart';
import 'shape_recognizer.dart';

/// Qué hace el dedo/lápiz sobre la hoja.
/// - draw: dibujar con la herramienta elegida.
/// - eraseStrokes: borrar trazos completos.
/// - pan: mover la hoja.
/// - text: tocar la hoja para escribir; tocar un texto para editarlo.
/// - select: mover, agrandar y girar textos y fotos (collage).
enum InputMode { draw, eraseStrokes, pan, text, select }

/// Color, grosor, sensibilidad a la presión y estabilización recordados por
/// herramienta (como en las apps de notas).
class ToolSettings {
  const ToolSettings(this.color, this.size, {this.pressure, this.stabilization});
  final int color;
  final double size;

  /// 0–1. null = lo propio de la herramienta.
  final double? pressure;
  final double? stabilization;

  ToolSettings copyWith({int? color, double? size, double? pressure, double? stabilization}) =>
      ToolSettings(
        color ?? this.color,
        size ?? this.size,
        pressure: pressure ?? this.pressure,
        stabilization: stabilization ?? this.stabilization,
      );
}

/// Valores por defecto de presión y estabilización de cada herramienta
/// (los mismos que usa el dibujo, en `stroke_renderer.dart`).
(double, double) defaultFeel(ToolType t) => switch (t) {
      ToolType.pen => (0.15, 0.5),
      ToolType.fountain => (0.55, 0.5),
      ToolType.pencil => (0.35, 0.35),
      ToolType.brush => (0.8, 0.6),
      _ => (0.0, 0.5),
    };

/// Estado del lienzo: herramientas, capas, deshacer/rehacer y guardado.
class DrawingController extends ChangeNotifier {
  DrawingController(this._drawing, {this.onSave});

  Drawing _drawing;
  Drawing get drawing => _drawing;

  /// Se llama (con retraso) después de cada cambio, para guardar en disco.
  final Future<void> Function(Drawing)? onSave;
  Timer? _saveTimer;
  bool _dirty = false;

  // ------------------------------------------------------------ Herramientas

  ToolType tool = ToolType.pen;
  InputMode mode = InputMode.draw;

  /// Si está activo, solo el lápiz óptico dibuja y el dedo mueve la hoja.
  bool stylusOnly = false;

  final Map<ToolType, ToolSettings> _settings = {
    ToolType.pen: const ToolSettings(0xFF1F2328, 4),
    ToolType.fountain: const ToolSettings(0xFFB3261E, 5),
    ToolType.pencil: const ToolSettings(0xFF3A3A3A, 3),
    ToolType.brush: const ToolSettings(0xFF1677FF, 14),
    ToolType.marker: const ToolSettings(0xFFE5484D, 10),
    ToolType.highlighter: const ToolSettings(0xFFFFD60A, 26),
    ToolType.eraser: const ToolSettings(0xFFFFFFFF, 30),
  };

  ToolSettings get settings => _settings[tool]!;
  ToolSettings settingsFor(ToolType t) => _settings[t]!;

  void selectTool(ToolType t) {
    tool = t;
    mode = InputMode.draw;
    selectedItemId = null;
    notifyListeners();
  }

  void selectMode(InputMode m) {
    mode = m;
    if (m != InputMode.select && m != InputMode.text) selectedItemId = null;
    notifyListeners();
  }

  void setColor(int color) {
    _settings[tool] = settings.copyWith(color: color);
    notifyListeners();
  }

  void setSize(double size) {
    _settings[tool] = settings.copyWith(size: size);
    notifyListeners();
  }

  void setFeel({double? pressure, double? stabilization}) {
    _settings[tool] = settings.copyWith(pressure: pressure, stabilization: stabilization);
    notifyListeners();
  }

  /// Colores rápidos de la barra (los últimos usados por herramienta).
  final Map<ToolType, List<int>> _recent = {};
  List<int> quickColors(ToolType t) {
    final defaults = t == ToolType.highlighter
        ? const [0xFFFFE14D, 0xFFFFB27A, 0xFF8EF08E, 0xFFA8C8FF, 0xFFD7A8FF]
        : const [0xFF000000, 0xFFB3261E, 0xFF2F55C0, 0xFF0B7A55, 0xFFE0A000];
    return _recent[t] ?? defaults;
  }

  void setQuickColor(int slot, int color) {
    final list = [...quickColors(tool)];
    if (slot < 0 || slot >= list.length) return;
    list[slot] = color;
    _recent[tool] = list;
    setColor(color);
  }

  // ------------------------------------------------------------- Formas

  /// Estilo para las formas nuevas.
  int shapeColor = 0xFF000000;
  double shapeStrokeWidth = 4;
  bool shapeFill = false;

  void setShapeStyle({int? color, double? strokeWidth, bool? fill}) {
    shapeColor = color ?? shapeColor;
    shapeStrokeWidth = strokeWidth ?? shapeStrokeWidth;
    shapeFill = fill ?? shapeFill;
    notifyListeners();
  }

  void toggleStylusOnly() {
    stylusOnly = !stylusOnly;
    notifyListeners();
  }

  // ------------------------------------------------------------------ Capas

  int _active = 0;
  int get activeLayerIndex => _active.clamp(0, _drawing.layers.length - 1);
  DrawingLayer get activeLayer => _drawing.layers[activeLayerIndex];

  void setActiveLayer(int i) {
    _active = i;
    notifyListeners();
  }

  void addLayer() {
    _commit(() {
      final n = _drawing.layers.length + 1;
      final layer = DrawingLayer(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        name: 'Capa $n',
      );
      final layers = [..._drawing.layers];
      layers.insert(activeLayerIndex + 1, layer); // encima de la activa
      _drawing = _drawing.copyWith(layers: layers);
      _active = activeLayerIndex + 1;
    });
  }

  void duplicateLayer(int i) {
    _commit(() {
      final src = _drawing.layers[i];
      final copy = DrawingLayer(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        name: '${src.name} (copia)',
        opacity: src.opacity,
        strokes: [...src.strokes],
        items: [for (final it in src.items) _cloneItem(it)],
      );
      _drawing = _drawing.copyWith(layers: [..._drawing.layers]..insert(i + 1, copy));
      _active = i + 1;
    });
  }

  void deleteLayer(int i) {
    if (_drawing.layers.length <= 1) return; // siempre queda una
    _commit(() {
      _drawing = _drawing.copyWith(layers: [..._drawing.layers]..removeAt(i));
      if (_active >= _drawing.layers.length) _active = _drawing.layers.length - 1;
    });
  }

  /// Nuevo orden de capas, de abajo hacia arriba, por id.
  void reorderLayers(List<String> idsBottomToTop) {
    _commit(() {
      final byId = {for (final l in _drawing.layers) l.id: l};
      final activeId = activeLayer.id;
      final layers = [for (final id in idsBottomToTop) byId[id]!];
      _drawing = _drawing.copyWith(layers: layers);
      _active = layers.indexWhere((l) => l.id == activeId);
    });
  }

  void updateLayer(int i, DrawingLayer Function(DrawingLayer) change,
      {bool undoable = true}) {
    void apply() {
      final layers = [..._drawing.layers];
      layers[i] = change(layers[i]);
      _drawing = _drawing.copyWith(layers: layers);
    }

    if (undoable) {
      _commit(apply);
    } else {
      apply();
      _changed();
    }
  }

  void clearLayer(int i) =>
      updateLayer(i, (l) => l.copyWith(strokes: const [], items: const []));

  // ------------------------------------------------ Textos y fotos (collage)

  String? selectedItemId;

  static int _idCounter = 0;
  static String newItemId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  CanvasItem _cloneItem(CanvasItem it) =>
      CanvasItem.fromJson({...it.toJson(), 'id': newItemId()})!;

  /// Capa y elemento con ese id (o null).
  (int, CanvasItem)? findItem(String? id) {
    if (id == null) return null;
    for (var i = 0; i < _drawing.layers.length; i++) {
      for (final it in _drawing.layers[i].items) {
        if (it.id == id) return (i, it);
      }
    }
    return null;
  }

  CanvasItem? get selectedItem => findItem(selectedItemId)?.$2;

  void selectItem(String? id) {
    selectedItemId = id;
    notifyListeners();
  }

  /// Agrega el elemento a la capa activa y lo deja seleccionado.
  void addItem(CanvasItem item) {
    if (!canDrawOnActiveLayer) return;
    _commit(() {
      final i = activeLayerIndex;
      final layers = [..._drawing.layers];
      layers[i] = layers[i].copyWith(items: [...layers[i].items, item]);
      _drawing = _drawing.copyWith(layers: layers);
      selectedItemId = item.id;
    });
  }

  /// Guarda un punto de "deshacer" antes de arrastrar/agrandar/girar, para
  /// que todo el gesto se deshaga de una vez.
  void beginItemChange() {
    _undo.add(_drawing);
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  void updateItem(String id, CanvasItem Function(CanvasItem) change,
      {bool undoable = true}) {
    final found = findItem(id);
    if (found == null) return;
    final (li, _) = found;
    void apply() {
      final layers = [..._drawing.layers];
      layers[li] = layers[li].copyWith(
        items: [for (final it in layers[li].items) it.id == id ? change(it) : it],
      );
      _drawing = _drawing.copyWith(layers: layers);
    }

    if (undoable) {
      _commit(apply);
    } else {
      apply();
      _changed();
    }
  }

  void removeItem(String id) {
    final found = findItem(id);
    if (found == null) return;
    final (li, _) = found;
    _commit(() {
      final layers = [..._drawing.layers];
      layers[li] = layers[li].copyWith(
          items: layers[li].items.where((it) => it.id != id).toList());
      _drawing = _drawing.copyWith(layers: layers);
      if (selectedItemId == id) selectedItemId = null;
    });
  }

  void duplicateItem(String id) {
    final it = findItem(id)?.$2;
    if (it == null) return;
    final copy = CanvasItem.fromJson({
      ...it.toJson(),
      'id': newItemId(),
      'x': it.x + 30,
      'y': it.y + 30,
    })!;
    final (li, _) = findItem(id)!;
    _commit(() {
      final layers = [..._drawing.layers];
      layers[li] = layers[li].copyWith(items: [...layers[li].items, copy]);
      _drawing = _drawing.copyWith(layers: layers);
      selectedItemId = copy.id;
    });
  }

  /// Pone el elemento encima (true) o debajo (false) de los demás de su capa.
  void reorderItem(String id, {required bool toFront}) {
    final found = findItem(id);
    if (found == null) return;
    final (li, item) = found;
    _commit(() {
      final layers = [..._drawing.layers];
      final rest = layers[li].items.where((it) => it.id != id).toList();
      layers[li] = layers[li].copyWith(items: toFront ? [...rest, item] : [item, ...rest]);
      _drawing = _drawing.copyWith(layers: layers);
    });
  }

  // ------------------------------------------------------------------- Hoja

  void setPaper(PaperStyle paper, {bool undoable = true}) {
    void apply() => _drawing = _drawing.copyWith(paper: paper);
    if (undoable) {
      _commit(apply);
    } else {
      apply();
      _changed();
    }
  }

  void toggleBookmark() {
    _drawing = _drawing.copyWith(bookmarked: !_drawing.bookmarked);
    _changed();
  }

  void setLandscape(bool landscape) {
    if (landscape == _drawing.isLandscape) return;
    _commit(() => _drawing =
        _drawing.copyWith(width: _drawing.height, height: _drawing.width));
  }

  // ----------------------------------------------------------------- Trazos

  Stroke? currentStroke;

  bool get canDrawOnActiveLayer => activeLayer.visible && !activeLayer.locked;

  /// True si el trazo actual ya se convirtió en figura (se ignoran más puntos).
  bool _snapped = false;

  /// [sizeScale] < 1 hace el trazo más fino (por ejemplo, con zoom alto).
  void startStroke(Offset at, double? pressure, {double sizeScale = 1}) {
    if (!canDrawOnActiveLayer) return;
    _snapped = false;
    currentStroke = Stroke(
      tool: tool,
      color: settings.color,
      size: (settings.size * sizeScale).clamp(0.5, 120),
      thinning: settings.pressure,
      streamline: settings.stabilization,
      points: [StrokePoint(at.dx, at.dy, pressure)],
    );
    notifyListeners();
  }

  void extendStroke(Offset at, double? pressure) {
    final s = currentStroke;
    if (s == null || _snapped) return;
    final last = s.points.last;
    // Ignorar movimientos mínimos (menos puntos = archivo más liviano).
    if ((Offset(last.x, last.y) - at).distanceSquared < 0.8) return;
    s.points.add(StrokePoint(at.dx, at.dy, pressure));
    notifyListeners();
  }

  void endStroke() {
    final s = currentStroke;
    if (s == null) return;
    currentStroke = null;
    _commit(() {
      final i = activeLayerIndex;
      final layers = [..._drawing.layers];
      layers[i] = layers[i].copyWith(strokes: [...layers[i].strokes, s]);
      _drawing = _drawing.copyWith(layers: layers);
    });
  }

  /// "Ajuste de figura": si el trazo actual parece una figura, lo reemplaza
  /// por la figura perfecta. Devuelve la figura reconocida (o null).
  RecognizedShape? snapCurrentStroke() {
    final s = currentStroke;
    if (s == null || _snapped) return null;
    if (s.tool == ToolType.eraser || s.tool == ToolType.highlighter) return null;
    final r = ShapeRecognizer.recognize(s.points);
    if (r == null) return null;
    _snapped = true;
    currentStroke = Stroke(
      tool: s.tool,
      color: s.color,
      size: s.size,
      thinning: s.thinning,
      streamline: s.streamline,
      points: r.$2,
    );
    notifyListeners();
    return r.$1;
  }

  /// Cancela el trazo (por ejemplo, al poner un segundo dedo para hacer zoom).
  void cancelStroke() {
    if (currentStroke == null) return;
    currentStroke = null;
    notifyListeners();
  }

  // ------------------------------------------------- Borrar trazos completos

  bool _erasingGesture = false;

  void beginEraseStrokes() => _erasingGesture = false;

  /// Borra los trazos de la capa activa que pasen cerca de [at].
  void eraseStrokesAt(Offset at, {double radius = 14}) {
    if (!canDrawOnActiveLayer) return;
    final layer = activeLayer;
    final keep = layer.strokes.where((s) => !_hits(s, at, radius)).toList();
    if (keep.length == layer.strokes.length) return;
    void apply() {
      final layers = [..._drawing.layers];
      layers[activeLayerIndex] = layer.copyWith(strokes: keep);
      _drawing = _drawing.copyWith(layers: layers);
    }

    // Un solo paso de "deshacer" por gesto, aunque borre varios trazos.
    if (!_erasingGesture) {
      _erasingGesture = true;
      _commit(apply);
    } else {
      apply();
      _changed();
    }
  }

  static bool _hits(Stroke s, Offset at, double radius) {
    if (!s.bounds.inflate(radius).contains(at)) return false;
    final r = radius + s.size / 2;
    final r2 = r * r;
    for (var i = 0; i < s.points.length; i++) {
      final a = Offset(s.points[i].x, s.points[i].y);
      if ((a - at).distanceSquared <= r2) return true;
      if (i + 1 < s.points.length) {
        final b = Offset(s.points[i + 1].x, s.points[i + 1].y);
        if (_distToSegment(at, a, b) <= r) return true;
      }
    }
    return false;
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  // ------------------------------------------------------ Deshacer / Rehacer

  final List<Drawing> _undo = [];
  final List<Drawing> _redo = [];
  static const _maxHistory = 60;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Las capas y listas de trazos son inmutables, así que guardar una "foto"
  /// del dibujo anterior es barato (solo referencias).
  void _commit(VoidCallback change) {
    _undo.add(_drawing);
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
    change();
    _changed();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_drawing);
    _drawing = _undo.removeLast();
    if (findItem(selectedItemId) == null) selectedItemId = null;
    _changed();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_drawing);
    _drawing = _redo.removeLast();
    if (findItem(selectedItemId) == null) selectedItemId = null;
    _changed();
  }

  // ---------------------------------------------------------------- Guardar

  void _changed() {
    _dirty = true;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    if (!_dirty || onSave == null) return;
    _dirty = false;
    await onSave!(_drawing);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  /// Presión normalizada de un evento de puntero (null = simular).
  static double? normalizePressure(
      {required bool isStylus, required double pressure, required double min, required double max}) {
    if (!isStylus || max <= min) return null;
    return ((pressure - min) / (max - min)).clamp(0.05, 1.0);
  }

  static double clampSize(double v) => math.max(1, math.min(80, v));
}
