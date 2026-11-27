import 'package:flutter/material.dart';

import '../../../../core/fonts.dart';
import '../../domain/drawing.dart';
import 'tool_panels.dart' show fullPalette, pickColor;
import '../../../../core/widgets/doodle_icon.dart';

/// Colores de fondo tipo etiqueta / cinta para los textos del collage.
const textBackgrounds = <int>[
  0xFFFFF1A8, 0xFFFFD6E0, 0xFFD7F0FF, 0xFFDDF5D3, 0xFFEADCFF, 0xFFFFE3C7, 0xFF1F2328,
];

/// Barra de formato del texto que se escribe directo en la hoja (va sobre
/// el teclado, como en StarNote): fuente, tamaño − / +, interlineado,
/// negrita, cursiva, subrayado, tachado, alineación, color y fondo.
class TextStyleBar extends StatelessWidget {
  const TextStyleBar({super.key, required this.item, required this.onChanged, required this.onDone});
  final TextItem item;
  final ValueChanged<TextItem> onChanged;
  final VoidCallback onDone;

  void _set(TextItem Function(TextItem) f) => onChanged(f(item));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = allFonts().where((f) => f.family == item.font).firstOrNull?.label.split(' · ').first ??
        'Fuente predeterminada';

    Widget pill({required Widget child, VoidCallback? onTap}) => Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: child,
            ),
          ),
        );

    Widget toggle(IconData icon, String tip, bool on, VoidCallback onTap) => IconButton(
          tooltip: tip,
          isSelected: on,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(backgroundColor: on ? scheme.primaryContainer : null),
          icon: Icon(icon),
          onPressed: onTap,
        );

    final lh = item.lineHeight.toStringAsFixed(item.lineHeight == 1.25 ? 2 : 1);

    return Material(
      color: scheme.surface,
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  pill(
                    onTap: () async {
                      final f = await pickFont(context, item.font);
                      if (f != null) _set((t) => t.copyWith(font: f.family, clearFont: f.family == null));
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 130),
                          child: Text(label,
                              overflow: TextOverflow.ellipsis, style: fontStyle(item.font, size: 15)),
                        ),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  pill(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _set((t) => t.copyWith(size: (t.size - 2).clamp(8, 240))),
                          child: const Icon(Icons.remove, size: 20),
                        ),
                        SizedBox(width: 36, child: Text('${item.size.round()}', textAlign: TextAlign.center)),
                        InkWell(
                          onTap: () => _set((t) => t.copyWith(size: (t.size + 2).clamp(8, 240))),
                          child: const Icon(Icons.add, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<double>(
                    tooltip: 'Interlineado',
                    onSelected: (v) => _set((t) => t.copyWith(lineHeight: v)),
                    itemBuilder: (_) => [
                      for (final v in const [1.0, 1.25, 1.5, 2.0])
                        PopupMenuItem(value: v, child: Text('${v.toStringAsFixed(v == 1.25 ? 2 : 1)}X')),
                    ],
                    child: pill(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Text('${lh}X'), const Icon(Icons.expand_more, size: 18)],
                      ),
                    ),
                  ),
                  toggle(Icons.format_bold, 'Negrita', item.bold, () => _set((t) => t.copyWith(bold: !t.bold))),
                  toggle(Icons.format_italic, 'Cursiva', item.italic,
                      () => _set((t) => t.copyWith(italic: !t.italic))),
                  toggle(Icons.format_underlined, 'Subrayado', item.underline,
                      () => _set((t) => t.copyWith(underline: !t.underline))),
                  toggle(Icons.format_strikethrough, 'Tachado', item.strike,
                      () => _set((t) => t.copyWith(strike: !t.strike))),
                  IconButton(
                    tooltip: 'Alineación',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(switch (item.align) {
                      TextItemAlign.left => Icons.format_align_left,
                      TextItemAlign.center => Icons.format_align_center,
                      TextItemAlign.right => Icons.format_align_right,
                    }),
                    onPressed: () =>
                        _set((t) => t.copyWith(align: TextItemAlign.values[(t.align.index + 1) % 3])),
                  ),
                  IconButton(
                    tooltip: 'Listo',
                    icon: Icon(Icons.check_circle, color: scheme.primary),
                    onPressed: onDone,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _RainbowDot(onTap: () async {
                    final c = await pickColor(context, current: item.color);
                    if (c != null) _set((t) => t.copyWith(color: c));
                  }),
                  for (final c in fullPalette.take(18))
                    _Dot(color: c, selected: item.color == c, onTap: () => _set((t) => t.copyWith(color: c))),
                  const VerticalDivider(width: 18),
                  _Dot(
                    color: null,
                    selected: item.background == null,
                    onTap: () => _set((t) => t.copyWith(clearBackground: true)),
                  ),
                  for (final c in textBackgrounds)
                    _Dot(
                      color: c,
                      square: true,
                      selected: item.background == c,
                      onTap: () => _set((t) => t.copyWith(background: c)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Elegir fuente, con vista previa en la propia letra.
Future<AppFont?> pickFont(BuildContext context, String? current) {
  return showModalBottomSheet<AppFont>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: ListView(
        children: [
          for (final group in FontGroup.values) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(group.label, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
            if (group == FontGroup.mine) const ImportFontTile(),
                for (final f in allFonts().where((f) => f.group == group))
              ListTile(
                selected: f.family == current,
                title: Text(f.label),
                subtitle: DoodleText(f.sample ?? 'Así se verá tu texto', style: fontStyle(f.family, size: 24)),
                onTap: () => Navigator.pop(context, f),
              ),
          ],
        ],
      ),
    ),
  );
}

class _RainbowDot extends StatelessWidget {
  const _RainbowDot({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: [
              Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red,
            ]),
          ),
          child: const Icon(Icons.add, size: 16, color: Colors.white),
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.selected, required this.onTap, this.square = false});
  final int? color;
  final bool selected;
  final bool square;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: color == null ? Colors.white : Color(color!),
          shape: square ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: square ? BorderRadius.circular(7) : null,
          border: Border.all(width: selected ? 3 : 1, color: selected ? primary : Colors.black26),
        ),
        child: color == null ? const Icon(Icons.block, size: 16, color: Colors.black38) : null,
      ),
    );
  }
}
