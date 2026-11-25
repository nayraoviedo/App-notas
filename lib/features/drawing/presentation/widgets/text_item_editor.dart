import 'package:flutter/material.dart';

import '../../../../core/fonts.dart';
import '../../domain/drawing.dart';
import 'canvas_item_view.dart';
import 'tool_settings_sheet.dart' show drawingPalette;

/// Colores de fondo tipo etiqueta / cinta para los textos del collage.
const textBackgrounds = <int>[
  0xFFFFF1A8, 0xFFFFD6E0, 0xFFD7F0FF, 0xFFDDF5D3, 0xFFEADCFF, 0xFFFFE3C7, 0xFF1F2328,
];

/// Escribir o editar un texto sobre la hoja: fuente (incluidas cursivas y
/// chinas), tamaño, color, negrita, cursiva, alineación y fondo.
/// Devuelve el texto editado, o null si se canceló.
Future<TextItem?> showTextItemEditor(BuildContext context, TextItem initial) {
  return showModalBottomSheet<TextItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: _TextItemEditor(initial: initial),
      ),
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
    final label = appFonts.where((f) => f.family == _item.font).firstOrNull?.label ?? 'Sistema';

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _item.copyWith(text: _text.text)),
                  child: const Text('Listo'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                // Vista previa con el estilo real.
                Container(
                  constraints: const BoxConstraints(minHeight: 90),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: TextField(
                    controller: _text,
                    autofocus: widget.initial.text.isEmpty,
                    maxLines: null,
                    textAlign: textItemAlign(_item),
                    style: textItemStyle(_item).copyWith(
                      fontSize: _item.size.clamp(14, 44),
                      backgroundColor:
                          _item.background == null ? null : Color(_item.background!),
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Escribe aquí…',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.text_fields, size: 18),
                      label: Text(label),
                      onPressed: () async {
                        final f = await _pickFont(context, _item.font);
                        if (f != null) {
                          _set((t) => t.copyWith(font: f.family, clearFont: f.family == null));
                        }
                      },
                    ),
                    const Spacer(),
                    IconButton(
                      isSelected: _item.bold,
                      icon: const Icon(Icons.format_bold),
                      onPressed: () => _set((t) => t.copyWith(bold: !t.bold)),
                    ),
                    IconButton(
                      isSelected: _item.italic,
                      icon: const Icon(Icons.format_italic),
                      onPressed: () => _set((t) => t.copyWith(italic: !t.italic)),
                    ),
                    IconButton(
                      icon: Icon(switch (_item.align) {
                        TextItemAlign.left => Icons.format_align_left,
                        TextItemAlign.center => Icons.format_align_center,
                        TextItemAlign.right => Icons.format_align_right,
                      }),
                      onPressed: () => _set((t) => t.copyWith(
                          align: TextItemAlign.values[(t.align.index + 1) % 3])),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Tamaño'),
                    Expanded(
                      child: Slider(
                        min: 12,
                        max: 140,
                        value: _item.size.clamp(12, 140),
                        onChanged: (v) => _set((t) => t.copyWith(size: v)),
                      ),
                    ),
                    SizedBox(width: 36, child: Text('${_item.size.round()}')),
                  ],
                ),
                const Text('Color de la letra'),
                const SizedBox(height: 8),
                _ColorRow(
                  colors: drawingPalette,
                  selected: _item.color,
                  onPick: (c) => _set((t) => t.copyWith(color: c)),
                ),
                const SizedBox(height: 16),
                const Text('Fondo (etiqueta)'),
                const SizedBox(height: 8),
                _ColorRow(
                  colors: textBackgrounds,
                  selected: _item.background,
                  allowNone: true,
                  onPick: (c) => _set((t) =>
                      c == null ? t.copyWith(clearBackground: true) : t.copyWith(background: c)),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Ancho del cuadro'),
                    Expanded(
                      child: Slider(
                        min: 120,
                        max: 950,
                        value: _item.width.clamp(120, 950),
                        onChanged: (v) => _set((t) => t.copyWith(width: v)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: FittedBox(child: CanvasItemContent(item: _item.copyWith(text: _text.text))),
                ),
              ],
            ),
          ),
        ],
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

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.colors,
    required this.selected,
    required this.onPick,
    this.allowNone = false,
  });

  final List<int> colors;
  final int? selected;
  final ValueChanged<int?> onPick;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    Widget dot(int? c) => GestureDetector(
          onTap: () => onPick(c),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c == null ? Colors.white : Color(c),
              shape: BoxShape.circle,
              border: Border.all(
                width: selected == c ? 3 : 1,
                color: selected == c ? primary : Colors.black26,
              ),
            ),
            child: c == null ? const Icon(Icons.block, size: 18, color: Colors.black38) : null,
          ),
        );
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (allowNone) dot(null),
        for (final c in colors) dot(c),
      ],
    );
  }
}
