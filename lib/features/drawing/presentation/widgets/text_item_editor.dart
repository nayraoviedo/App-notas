import 'package:flutter/material.dart';

import '../../../../core/fonts.dart';
import '../../domain/drawing.dart';
import 'canvas_item_view.dart';
import 'tool_settings_sheet.dart' show drawingPalette;

/// Colores de fondo tipo etiqueta / cinta para los textos del collage.
const textBackgrounds = <int>[
  0xFFFFF1A8, 0xFFFFD6E0, 0xFFD7F0FF, 0xFFDDF5D3, 0xFFEADCFF, 0xFFFFE3C7, 0xFF1F2328,
];

/// Escribir o editar un texto sobre la hoja, con una barra compacta sobre el
/// teclado (como StarNote): fuente, tamaño − / +, interlineado, negrita,
/// cursiva, alineación, color y fondo tipo etiqueta.
/// Devuelve el texto editado, o null si se canceló.
Future<TextItem?> showTextItemEditor(BuildContext context, TextItem initial) {
  return showModalBottomSheet<TextItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _TextItemEditor(initial: initial),
    ),
  );
}

class _TextItemEditor extends StatefulWidget {
  const _TextItemEditor({required this.initial});
  final TextItem initial;

  @override
  State<_TextItemEditor> createState() => _TextItemEditorState();
}

class _TextItemEditorState extends State<_TextItemEditor> {
  late TextItem _item = widget.initial;
  late final _text = TextEditingController(text: widget.initial.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _set(TextItem Function(TextItem) f) => setState(() => _item = f(_item));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = appFonts.where((f) => f.family == _item.font).firstOrNull?.label.split(' · ').first ??
        'Fuente predeterminada';

    Widget pill({required Widget child, VoidCallback? onTap}) => Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: child,
            ),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _item.copyWith(text: _text.text)),
                  child: const Text('Listo'),
                ),
              ],
            ),
            // Cuadro de texto con el estilo real, como en la hoja.
            Container(
              constraints: const BoxConstraints(minHeight: 70, maxHeight: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _item.background == null ? Colors.white : Color(_item.background!),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.primary, width: 1.5),
              ),
              child: TextField(
                controller: _text,
                autofocus: true,
                maxLines: null,
                textAlign: textItemAlign(_item),
                style: textItemStyle(_item).copyWith(fontSize: _item.size.clamp(14, 40)),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Escribe aquí…',
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Fuente · tamaño · interlineado · B · I · alineación
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  pill(
                    onTap: () async {
                      final f = await _pickFont(context, _item.font);
                      if (f != null) {
                        _set((t) => t.copyWith(font: f.family, clearFont: f.family == null));
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(label,
                              overflow: TextOverflow.ellipsis,
                              style: fontStyle(_item.font, size: 15)),
                        ),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  pill(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _set((t) => t.copyWith(size: (t.size - 2).clamp(8, 200))),
                          child: const Icon(Icons.remove, size: 20),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text('${_item.size.round()}', textAlign: TextAlign.center),
                        ),
                        InkWell(
                          onTap: () => _set((t) => t.copyWith(size: (t.size + 2).clamp(8, 200))),
                          child: const Icon(Icons.add, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
                        children: [
                          Text('${_item.lineHeight.toStringAsFixed(_item.lineHeight == 1.25 ? 2 : 1)}X'),
                          const Icon(Icons.expand_more, size: 18),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    isSelected: _item.bold,
                    tooltip: 'Negrita',
                    icon: const Icon(Icons.format_bold),
                    onPressed: () => _set((t) => t.copyWith(bold: !t.bold)),
                  ),
                  IconButton(
                    isSelected: _item.italic,
                    tooltip: 'Cursiva',
                    icon: const Icon(Icons.format_italic),
                    onPressed: () => _set((t) => t.copyWith(italic: !t.italic)),
                  ),
                  IconButton(
                    tooltip: 'Alineación',
                    icon: Icon(switch (_item.align) {
                      TextItemAlign.left => Icons.format_align_left,
                      TextItemAlign.center => Icons.format_align_center,
                      TextItemAlign.right => Icons.format_align_right,
                    }),
                    onPressed: () =>
                        _set((t) => t.copyWith(align: TextItemAlign.values[(t.align.index + 1) % 3])),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Color de la letra | fondo tipo etiqueta
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in drawingPalette)
                    _Dot(
                      color: c,
                      selected: _item.color == c,
                      onTap: () => _set((t) => t.copyWith(color: c)),
                    ),
                  const VerticalDivider(width: 18),
                  _Dot(
                    color: null,
                    selected: _item.background == null,
                    onTap: () => _set((t) => t.copyWith(clearBackground: true)),
                  ),
                  for (final c in textBackgrounds)
                    _Dot(
                      color: c,
                      square: true,
                      selected: _item.background == c,
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

  Future<AppFont?> _pickFont(BuildContext context, String? current) {
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
                child: Text(group.label,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ),
              for (final f in appFonts.where((f) => f.group == group))
                ListTile(
                  selected: f.family == current,
                  title: Text(f.label),
                  subtitle: Text(f.sample ?? 'Así se verá tu texto',
                      style: fontStyle(f.family, size: 22)),
                  onTap: () => Navigator.pop(context, f),
                ),
            ],
          ],
        ),
      ),
    );
  }
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
