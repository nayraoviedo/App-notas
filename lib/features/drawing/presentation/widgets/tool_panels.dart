import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/fonts.dart';
import '../../application/drawing_controller.dart';
import '../../domain/drawing.dart';
import '../painters/shape_painter.dart';
import '../painters/sticker_painter.dart';

/// Panel flotante que se abre bajo la barra de herramientas (como StarNote).
enum ToolPanel { none, pen, highlighter, eraser, shapes, stickers, tape }

/// Plumas del estuche, en el orden del panel.
const penTools = [ToolType.fountain, ToolType.pen, ToolType.brush, ToolType.marker, ToolType.pencil];

IconData toolIcon(ToolType t) => switch (t) {
      ToolType.fountain => Icons.history_edu,
      ToolType.pen => Icons.edit,
      ToolType.brush => Icons.brush,
      ToolType.marker => Icons.border_color,
      ToolType.pencil => Icons.create_outlined,
      ToolType.highlighter => Icons.highlight,
      ToolType.eraser => Icons.auto_fix_normal,
      ToolType.tape => Icons.linear_scale,
    };

/// Paleta completa: neutros, tintas, pasteles, tonos tierra y neón.
const fullPalette = <int>[
  // Neutros
  0xFF000000, 0xFF3C4043, 0xFF5C6370, 0xFF9AA0A6, 0xFFDADCE0, 0xFFFFFFFF,
  // Tintas
  0xFFB3261E, 0xFFE5484D, 0xFFFF8A3D, 0xFFE0A000, 0xFF0B7A55, 0xFF12A594,
  0xFF2F55C0, 0xFF1677FF, 0xFF6E56CF, 0xFF8E24AA, 0xFFD6409F, 0xFF8D6E63,
  // Pasteles
  0xFFFFB4C6, 0xFFF8BBD0, 0xFFFFCCBC, 0xFFFFE0B2, 0xFFFFF59D, 0xFFDCEDC8,
  0xFFB2DFDB, 0xFFB3E5FC, 0xFFC5CAE9, 0xFFE1BEE7, 0xFFD7CCC8, 0xFFCFD8DC,
  // Tierra / vintage
  0xFF7B4B2A, 0xFFA0522D, 0xFFC4915E, 0xFFD9CBB4, 0xFF97B3A5, 0xFF4F7189,
  // Neón (resaltadores)
  0xFFFFEA00, 0xFF39FF14, 0xFF00E5FF, 0xFFFF3EA5, 0xFFFF6D00, 0xFFB388FF,
];

/// Tarjeta blanca con título, como los paneles de StarNote.
class PanelCard extends StatelessWidget {
  const PanelCard({super.key, this.title, required this.child, this.maxHeight = 520});
  final String? title;
  final Widget child;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 10,
      shadowColor: Colors.black26,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(title!,
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              ),
              const Divider(height: 1),
            ],
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeStart,
    this.divisions,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(valueLabel, style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 4),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Slider(
              min: min,
              max: max,
              divisions: divisions,
              value: value.clamp(min, max),
              onChangeStart: onChangeStart,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de 5 colores rápidos. Tocar el elegido abre la paleta para cambiarlo.
class QuickColorRow extends StatelessWidget {
  const QuickColorRow({
    super.key,
    required this.colors,
    required this.selected,
    required this.onPick,
    required this.onReplace,
    this.size = 34,
  });

  final List<int> colors;
  final int selected;
  final ValueChanged<int> onPick;

  /// Cambiar el color de un lugar (índice) por otro de la paleta.
  final void Function(int slot, int color) onReplace;
  final double size;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Más colores: reemplaza el color elegido por uno de la paleta.
        GestureDetector(
          onTap: () async {
            final c = await pickColor(context, current: selected);
            if (c == null) return;
            final slot = colors.indexOf(selected);
            onReplace(slot < 0 ? 0 : slot, c);
          },
          child: Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [
                  Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red,
                ]),
              ),
              child: Icon(Icons.add, size: size * 0.5, color: Colors.white),
            ),
          ),
        ),
        for (var i = 0; i < colors.length; i++)
          GestureDetector(
            onTap: () async {
              if (colors[i] == selected) {
                final c = await pickColor(context, current: selected);
                if (c != null) onReplace(i, c);
              } else {
                onPick(colors[i]);
              }
            },
            child: Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors[i] == selected ? primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Color(colors[i]),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12),
                ),
                child: colors[i] == selected
                    ? Icon(Icons.expand_more,
                        size: size * 0.5,
                        color: Color(colors[i]).computeLuminance() > 0.5 ? Colors.black54 : Colors.white)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

Future<int?> pickColor(BuildContext context, {int? current}) => showDialog<int>(
      context: context,
      builder: (_) => _ColorPickerDialog(current: current),
    );

/// Paleta + color personalizado (tono, intensidad y brillo).
class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({this.current});
  final int? current;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.current ?? 0xFFE5484D));
  bool _custom = false;

  /// "Mis colores": favoritos guardados en el teléfono.
  List<int> _favorites = const [];
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _prefs = p;
        _favorites = [
          for (final v in p.getStringList('colors.favorites') ?? const <String>[])
            if (int.tryParse(v) case final c?) c,
        ];
      });
    });
  }

  Future<void> _saveFavorites(List<int> list) async {
    setState(() => _favorites = list);
    await _prefs?.setStringList('colors.favorites', [for (final c in list) '$c']);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final color = _hsv.toColor();
    Widget slider(String label, double value, double max, ValueChanged<double> onChanged,
            List<Color> track) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Container(
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: LinearGradient(colors: track),
              ),
            ),
            Slider(value: value, max: max, onChanged: onChanged),
          ],
        );

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Elige un color')),
          TextButton(
            onPressed: () => setState(() => _custom = !_custom),
            child: Text(_custom ? 'Paleta' : 'Personalizado'),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: _custom
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    slider('Tono', _hsv.hue, 360, (v) => setState(() => _hsv = _hsv.withHue(v)), [
                      for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
                    ]),
                    slider('Intensidad', _hsv.saturation, 1,
                        (v) => setState(() => _hsv = _hsv.withSaturation(v)),
                        [_hsv.withSaturation(0).toColor(), _hsv.withSaturation(1).toColor()]),
                    slider('Brillo', _hsv.value, 1, (v) => setState(() => _hsv = _hsv.withValue(v)),
                        [Colors.black, _hsv.withValue(1).toColor()]),
                  ],
                )
              : Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    if (_favorites.isNotEmpty) ...[
                      const SizedBox(width: double.infinity, child: Text('Mis colores (mantén para quitar)')),
                      for (final c in _favorites)
                        GestureDetector(
                          onTap: () => Navigator.pop(context, c),
                          onLongPress: () => _saveFavorites([..._favorites]..remove(c)),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(c),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.black26),
                            ),
                          ),
                        ),
                      const SizedBox(width: double.infinity, child: Divider()),
                    ],
                    for (final c in fullPalette)
                      GestureDetector(
                        onTap: () => Navigator.pop(context, c),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              width: c == widget.current ? 3 : 1,
                              color: c == widget.current ? primary : Colors.black26,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        if (_custom)
          TextButton(
            onPressed: () {
              final c = color.toARGB32();
              if (!_favorites.contains(c)) _saveFavorites([..._favorites, c]);
              setState(() => _custom = false); // mostrarlo en "Mis colores"
            },
            child: const Text('♡ Guardar'),
          ),
        if (_custom)
          FilledButton(
            onPressed: () => Navigator.pop(context, color.toARGB32()),
            child: const Text('Usar este color'),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Plumas

class PenPanel extends StatelessWidget {
  const PenPanel({super.key, required this.controller});
  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final t = c.tool;
        final s = c.settings;
        final (defPressure, defStab) = defaultFeel(t);
        final flat = t == ToolType.marker;
        return PanelCard(
          title: t.label,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // El estuche: la pluma elegida sobresale.
                SizedBox(
                  height: 118,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final p in penTools)
                        Tooltip(
                          message: p.label,
                          child: GestureDetector(
                            onTap: () => c.selectTool(p),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: EdgeInsets.only(bottom: p == t ? 18 : 0),
                              width: 34,
                              height: 96,
                              child: CustomPaint(
                                painter: PenGlyphPainter(p, Color(c.settingsFor(p).color)),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _SliderRow(
                  label: 'Sensibilidad a la presión',
                  valueLabel: flat ? '—' : '${((s.pressure ?? defPressure) * 100).round()}%',
                  value: flat ? 0 : (s.pressure ?? defPressure),
                  min: 0,
                  max: 1,
                  divisions: 10,
                  onChanged: flat ? null : (v) => c.setFeel(pressure: v),
                ),
                _SliderRow(
                  label: 'Espesor',
                  valueLabel: '${(s.size * 0.125).toStringAsFixed(2)}mm',
                  value: s.size,
                  min: 1,
                  max: 40,
                  onChanged: c.setSize,
                ),
                _SliderRow(
                  label: 'Estabilización de trazo',
                  valueLabel: '${((s.stabilization ?? defStab) * 100).round()}%',
                  value: s.stabilization ?? defStab,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  onChanged: (v) => c.setFeel(stabilization: v),
                ),
                const SizedBox(height: 14),
                const Text('Color'),
                const SizedBox(height: 6),
                QuickColorRow(
                  colors: c.quickColors(t),
                  selected: s.color,
                  onPick: c.setColor,
                  onReplace: c.setQuickColor,
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Solo lápiz óptico'),
                  subtitle: const Text('El dedo mueve la hoja'),
                  value: c.stylusOnly,
                  onChanged: (_) => c.toggleStylusOnly(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dibujito de una pluma para el estuche.
class PenGlyphPainter extends CustomPainter {
  const PenGlyphPainter(this.tool, this.color);
  final ToolType tool;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bodyTop = h * 0.42;
    final body = RRect.fromLTRBAndCorners(w * 0.12, bodyTop, w * 0.88, h,
        topLeft: const Radius.circular(4), topRight: const Radius.circular(4));
    final bodyColor = switch (tool) {
      ToolType.fountain => color,
      ToolType.pencil => const Color(0xFFB0B5BB),
      _ => const Color(0xFFA7ACB2),
    };
    canvas.drawRRect(body, Paint()..color = bodyColor);
    canvas.drawRect(Rect.fromLTWH(w * 0.12, bodyTop, w * 0.18, h - bodyTop),
        Paint()..color = Colors.white.withValues(alpha: 0.25));
    final tip = Path();
    switch (tool) {
      case ToolType.fountain:
        tip
          ..moveTo(w * 0.18, bodyTop)
          ..quadraticBezierTo(w * 0.2, h * 0.2, w / 2, 0)
          ..quadraticBezierTo(w * 0.8, h * 0.2, w * 0.82, bodyTop)
          ..close();
        canvas.drawPath(tip, Paint()..color = const Color(0xFFEDEDED));
        canvas.drawLine(Offset(w / 2, h * 0.05), Offset(w / 2, bodyTop - 8),
            Paint()
              ..color = color
              ..strokeWidth = 1.5);
        canvas.drawCircle(Offset(w / 2, bodyTop - 8), 2.5, Paint()..color = color);
      case ToolType.pencil:
        tip
          ..moveTo(w * 0.12, bodyTop)
          ..lineTo(w / 2, 0)
          ..lineTo(w * 0.88, bodyTop)
          ..close();
        canvas.drawPath(tip, Paint()..color = const Color(0xFFF1D9B5));
        canvas.drawPath(
            Path()
              ..moveTo(w * 0.38, h * 0.12)
              ..lineTo(w / 2, 0)
              ..lineTo(w * 0.62, h * 0.12)
              ..close(),
            Paint()..color = color);
      case ToolType.brush:
        tip
          ..moveTo(w * 0.25, bodyTop)
          ..quadraticBezierTo(w * 0.2, h * 0.15, w / 2, 0)
          ..quadraticBezierTo(w * 0.8, h * 0.15, w * 0.75, bodyTop)
          ..close();
        canvas.drawPath(tip, Paint()..color = color);
      case ToolType.marker:
      case ToolType.highlighter:
        tip
          ..moveTo(w * 0.22, bodyTop)
          ..lineTo(w * 0.3, h * 0.12)
          ..lineTo(w * 0.7, h * 0.04)
          ..lineTo(w * 0.78, bodyTop)
          ..close();
        canvas.drawPath(tip, Paint()..color = color);
      case ToolType.pen:
      case ToolType.eraser:
      case ToolType.tape:
        tip
          ..moveTo(w * 0.15, bodyTop)
          ..lineTo(w * 0.42, h * 0.08)
          ..lineTo(w * 0.58, h * 0.08)
          ..lineTo(w * 0.85, bodyTop)
          ..close();
        canvas.drawPath(tip, Paint()..color = const Color(0xFF8D9399));
        canvas.drawRect(Rect.fromLTWH(w * 0.44, 0, w * 0.12, h * 0.09), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(PenGlyphPainter old) => old.tool != tool || old.color != color;
}

// --------------------------------------------------------------- Resaltador

class HighlighterPanel extends StatelessWidget {
  const HighlighterPanel({super.key, required this.controller, this.tool = ToolType.highlighter});
  final DrawingController controller;
  final ToolType tool;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final s = c.settingsFor(tool);
          return PanelCard(
            title: tool == ToolType.tape ? 'Cinta washi: arrástrala sobre la hoja' : 'Resaltador',
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SliderRow(
                    label: 'Espesor',
                    valueLabel: '${(s.size * 0.125).toStringAsFixed(2)}mm',
                    value: s.size,
                    min: 6,
                    max: 80,
                    onChanged: c.setSize,
                  ),
                  const SizedBox(height: 14),
                  const Text('Color'),
                  const SizedBox(height: 6),
                  QuickColorRow(
                    colors: c.quickColors(tool),
                    selected: s.color,
                    onPick: c.setColor,
                    onReplace: c.setQuickColor,
                  ),
                ],
              ),
            ),
          );
        },
      );
}

// ----------------------------------------------------------------- Borrador

class EraserPanel extends StatelessWidget {
  const EraserPanel({super.key, required this.controller});
  final DrawingController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final whole = c.mode == InputMode.eraseStrokes;
          return PanelCard(
            title: 'Borrador',
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Por área')),
                      ButtonSegment(value: true, label: Text('Trazo completo')),
                    ],
                    selected: {whole},
                    onSelectionChanged: (v) => v.first
                        ? c.selectMode(InputMode.eraseStrokes)
                        : c.selectTool(ToolType.eraser),
                  ),
                  if (!whole)
                    _SliderRow(
                      label: 'Tamaño',
                      valueLabel: '${c.settingsFor(ToolType.eraser).size.round()}',
                      value: c.settingsFor(ToolType.eraser).size,
                      min: 6,
                      max: 80,
                      onChanged: (v) {
                        if (c.tool != ToolType.eraser) c.selectTool(ToolType.eraser);
                        c.setSize(v);
                      },
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Borrar todo en esta capa'),
                    onPressed: () => c.clearLayer(c.activeLayerIndex),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

// ------------------------------------------------------------------- Formas

class ShapesPanel extends StatelessWidget {
  const ShapesPanel({super.key, required this.controller, required this.onInsert});
  final DrawingController controller;
  final ValueChanged<ShapeKind> onInsert;

  /// Color de relleno: el mismo del trazo, suave.
  static int fillFor(int color) => (color & 0x00FFFFFF) | 0x59000000;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final sel = c.selectedItem;
          final editing = sel is ShapeItem ? sel : null;
          final color = editing?.color ?? c.shapeColor;
          final width = editing?.strokeWidth ?? c.shapeStrokeWidth;
          final fill = editing != null ? editing.fill != null : c.shapeFill;
          final scheme = Theme.of(context).colorScheme;

          void apply({int? color, double? width, bool? fill, bool undoable = true}) {
            c.setShapeStyle(color: color, strokeWidth: width, fill: fill);
            if (editing != null) {
              c.updateItem(editing.id, (it) {
                final sh = it as ShapeItem;
                final newColor = color ?? sh.color;
                final hasFill = fill ?? sh.fill != null;
                return sh.copyWith(
                  color: newColor,
                  strokeWidth: width,
                  fill: hasFill ? fillFor(newColor) : null,
                  clearFill: !hasFill,
                );
              }, undoable: undoable);
            }
          }

          return PanelCard(
            title: editing == null ? 'Forma' : 'Forma: ${editing.shape.label}',
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (editing == null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text('Toca una forma para ponerla en la hoja',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    ),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 6,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        for (final k in ShapeKind.values)
                          Tooltip(
                            message: k.label,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => onInsert(k),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: scheme.outlineVariant),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.all(9),
                                child: CustomPaint(
                                  painter: _ShapeIconPainter(k),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  _SliderRow(
                    label: 'Grosor del trazo',
                    valueLabel: '${(width * 0.075).toStringAsFixed(2)}mm',
                    value: width,
                    min: 1,
                    max: 24,
                    onChangeStart: (_) {
                      if (editing != null) c.beginItemChange();
                    },
                    onChanged: (v) => apply(width: v, undoable: false),
                  ),
                  const SizedBox(height: 14),
                  const Text('Color del trazo'),
                  const SizedBox(height: 6),
                  QuickColorRow(
                    colors: const [0xFF000000, 0xFFB3261E, 0xFF2F55C0, 0xFF0B7A55, 0xFFE0A000],
                    selected: color,
                    onPick: (v) => apply(color: v),
                    onReplace: (_, v) => apply(color: v),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text('Relleno de forma'),
                    value: fill,
                    onChanged: (v) => apply(fill: v),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

/// Ícono de una forma, centrado y con proporción fija.
class _ShapeIconPainter extends CustomPainter {
  const _ShapeIconPainter(this.kind);
  final ShapeKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final (w, h) = kind.defaultSize;
    final k = (size.width / w) < (size.height / h) ? size.width / w : size.height / h;
    final s = Size(w * k, h * k);
    canvas.save();
    canvas.translate((size.width - s.width) / 2, (size.height - s.height) / 2);
    paintShape(canvas, kind, s, color: Colors.black87, strokeWidth: 1.6);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShapeIconPainter old) => old.kind != kind;
}

// ----------------------------------------------------------------- Stickers

class StickersPanel extends StatefulWidget {
  const StickersPanel({
    super.key,
    required this.onSticker,
    required this.onTextSticker,
    required this.onEmoji,
    this.custom = const [],
    this.onCustom,
    this.onAddCustom,
    this.onDeleteCustom,
  });

  /// Stickers propios (rutas de imágenes).
  final List<String> custom;
  final ValueChanged<String>? onCustom;
  final VoidCallback? onAddCustom;
  final ValueChanged<String>? onDeleteCustom;

  final ValueChanged<StickerDef> onSticker;
  final ValueChanged<TextSticker> onTextSticker;
  final ValueChanged<String> onEmoji;

  @override
  State<StickersPanel> createState() => _StickersPanelState();
}

class _StickersPanelState extends State<StickersPanel> {
  static StickerCategory _tab = StickerCategory.memo;
  // Pestaña "Míos": mantener presionado un sticker para borrarlo.
  String _textGroup = 'Todos';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PanelCard(
      maxHeight: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final t in StickerCategory.values)
                  InkWell(
                    onTap: () => setState(() => _tab = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 2.5,
                            color: t == _tab ? scheme.primary : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Text(
                        t.label,
                        style: TextStyle(
                          fontSize: 18,
                          color: t == _tab ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(child: _content(scheme)),
        ],
      ),
    );
  }

  Widget _cell(Widget child, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          padding: const EdgeInsets.all(8),
          child: Center(child: child),
        ),
      );

  Widget _content(ColorScheme scheme) {
    switch (_tab) {
      case StickerCategory.mine:
        return GridView.count(
          crossAxisCount: 4,
          padding: const EdgeInsets.all(12),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          shrinkWrap: true,
          children: [
            _cell(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, color: scheme.primary),
                  const SizedBox(height: 2),
                  Text('Agregar', style: TextStyle(fontSize: 11, color: scheme.primary)),
                ],
              ),
              () => widget.onAddCustom?.call(),
            ),
            for (final path in widget.custom)
              GestureDetector(
                onLongPress: () => widget.onDeleteCustom?.call(path),
                child: _cell(Image.file(File(path), fit: BoxFit.contain), () => widget.onCustom?.call(path)),
              ),
          ],
        );
      case StickerCategory.text:
        final groups = ['Todos', 'Día', 'Mes', 'Título'];
        final list = textStickers.where((t) => _textGroup == 'Todos' || t.group == _textGroup).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final g in groups)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(g),
                        selected: g == _textGroup,
                        onSelected: (_) => setState(() => _textGroup = g),
                      ),
                    ),
                ],
              ),
            ),
            Flexible(
              child: GridView.count(
                crossAxisCount: 3,
                padding: const EdgeInsets.all(12),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.6,
                shrinkWrap: true,
                children: [
                  for (final t in list)
                    _cell(
                      FittedBox(
                        child: Container(
                          padding: t.background == null
                              ? EdgeInsets.zero
                              : const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: t.background == null
                              ? null
                              : BoxDecoration(
                                  color: Color(t.background!),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                          child: Text(t.text,
                              style: fontStyle(t.font, size: 24).copyWith(color: Color(t.color))),
                        ),
                      ),
                      () => widget.onTextSticker(t),
                    ),
                ],
              ),
            ),
          ],
        );
      case StickerCategory.emoji:
        return GridView.count(
          crossAxisCount: 6,
          padding: const EdgeInsets.all(12),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          shrinkWrap: true,
          children: [
            for (final e in emojiStickers)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.onEmoji(e),
                child: Center(child: Text(e, style: const TextStyle(fontSize: 30))),
              ),
          ],
        );
      default:
        return GridView.count(
          crossAxisCount: 4,
          padding: const EdgeInsets.all(12),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          shrinkWrap: true,
          children: [
            for (final s in stickersOf(_tab))
              _cell(
                AspectRatio(
                  aspectRatio: s.width / s.height,
                  child: CustomPaint(painter: StickerPainter(s.id)),
                ),
                () => widget.onSticker(s),
              ),
          ],
        );
    }
  }
}
