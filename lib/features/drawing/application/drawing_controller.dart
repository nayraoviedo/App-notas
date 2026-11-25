import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../domain/drawing.dart';

/// Qué hace el dedo/lápiz sobre la hoja.
enum InputMode { draw, eraseStrokes, pan }

/// Color y grosor recordados por herramienta (como en las apps de notas).
class ToolSettings {
  const ToolSettings(this.color, this.size);
  final int color;
  final double size;

  ToolSettings copyWith({int? color, double? size}) =>
      ToolSettings(color ?? this.color, size ?? this.size);
}

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
    notifyListeners();
  }

  void selectMode(InputMode m) {
    mode = m;
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

  void clearLayer(int i) => updateLayer(i, (l) => l.copyWith(strokes: const []));

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

  void setLandscape(bool landscape) {
    if (landscape == _drawing.isLandscape) return;
    _commit(() => _drawing =
        _drawing.copyWith(width: _drawing.height, height: _drawing.width));
  }

  // ----------------------------------------------------------------- Trazos

  Stroke? currentStroke;

  bool get canDrawOnActiveLayer => activeLayer.visible && !activeLayer.locked;

  void startStroke(Offset at, double? pressure) {
    if (!canDrawOnActiveLayer) return;
    currentStroke = Stroke(
      tool: tool,
      color: settings.color,
      size: settings.size,
      points: [StrokePoint(at.dx, at.dy, pressure)],
    );
    notifyListeners();
  }

  void extendStroke(Offset at, double? pressure) {
    final s = currentStroke;
    if (s == null) return;
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
    _changed();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_drawing);
    _drawing = _redo.removeLast();
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
