import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/fonts.dart';
import '../../../../core/providers.dart';
import '../../data/notes_repository.dart';
import '../../../drawing/presentation/widgets/tool_panels.dart' show pickColor;
import '../../domain/note_block.dart';
import '../../../study/presentation/study_screen.dart' show showNewFlashcard;
import 'highlight_text_controller.dart';

/// Bloque de texto con fuente y tamaño propios. Guarda solo, medio segundo
/// después de dejar de escribir. Al tocarlo aparece la barra de fuente.
/// Se puede resaltar lo seleccionado (como con un marcador) y cambiar el
/// color de la letra.
class TextBlockView extends ConsumerStatefulWidget {
  const TextBlockView({super.key, required this.block});
  final TextBlock block;

  @override
  ConsumerState<TextBlockView> createState() => _TextBlockViewState();
}

class _TextBlockViewState extends ConsumerState<TextBlockView> {
  late final _controller =
      HighlightTextController(text: widget.block.text, marks: widget.block.marks);
  Timer? _marksDebounce;
  bool _showMarker = false;
  final _focus = FocusNode();
  Timer? _debounce;
  late final NotesRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(notesRepositoryProvider); // para usarlo también en dispose()
    _focus.addListener(() => setState(() {}));
    // Guardar también los cambios automáticos (listas, casillas).
    var lastSaved = widget.block.text;
    _controller.addListener(() {
      if (_controller.text != lastSaved) {
        lastSaved = _controller.text;
        _onChanged(lastSaved);
      }
    });
    _controller.onMarksChanged = () {
      _marksDebounce?.cancel();
      _marksDebounce = Timer(const Duration(milliseconds: 500),
          () => _repo.updateMarks(widget.block.id, _controller.marks));
    };
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _repo.updateText(widget.block.id, text);
    });
  }

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      _repo.updateText(widget.block.id, _controller.text);
    }
    if (_marksDebounce?.isActive ?? false) {
      _marksDebounce!.cancel();
      _repo.updateMarks(widget.block.id, _controller.marks);
    }
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _list(String kind) {
    _controller.toggleList(kind);
    _onChanged(_controller.text);
  }

  Future<void> _setStyle({String? family, double? size, bool systemFont = false}) =>
      _repo.updateTextStyle(
        widget.block.id,
        fontFamily: systemFont ? null : (family ?? widget.block.fontFamily),
        fontSize: size ?? widget.block.fontSize,
      );

  Future<void> _pickFont() async {
    final current = widget.block.fontFamily;
    final chosen = await showModalBottomSheet<AppFont>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: SafeArea(
          child: ListView(
            children: [
              for (final group in FontGroup.values) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(group.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary)),
                ),
                for (final f in appFonts.where((f) => f.group == group))
                  ListTile(
                    selected: f.family == current,
                    title: Text(f.label),
                    // Vista previa con la propia fuente (la china se descarga
                    // la primera vez, puede tardar unos segundos).
                    subtitle: Text(
                      f.sample ?? 'Así se verán tus notas',
                      style: fontStyle(f.family, size: 22),
                    ),
                    trailing: f.family == current ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, f),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (chosen != null) {
      await _setStyle(family: chosen.family, systemFont: chosen.family == null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final base = Theme.of(context).textTheme.bodyLarge;
    var style = fontStyle(b.fontFamily, size: b.fontSize, base: base);
    if (b.textColor != null) style = style.copyWith(color: Color(b.textColor!));
    final label =
        appFonts.where((f) => f.family == b.fontFamily).firstOrNull?.label ??
            b.fontFamily ??
            'Sistema';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_focus.hasFocus)
          // Tocar la barra no debe quitar el foco del texto.
          TextFieldTapRegion(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.text_fields, size: 18),
                        label: Text(label),
                        onPressed: _pickFont,
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<double>(
                        value: fontSizes.contains(b.fontSize) ? b.fontSize : null,
                        hint: const Text('Tamaño'),
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final s in fontSizes)
                            DropdownMenuItem(value: s, child: Text('${s.round()}')),
                        ],
                        onChanged: (s) => _setStyle(size: s),
                      ),
                      IconButton(
                        tooltip: 'Color de la letra',
                        icon: Icon(Icons.format_color_text,
                            color: b.textColor == null ? null : Color(b.textColor!)),
                        onPressed: () async {
                          final c = await pickColor(context, current: b.textColor);
                          if (c != null) await _repo.updateTextColor(b.id, c);
                        },
                      ),
                      IconButton(
                        tooltip: 'Lista con viñetas',
                        icon: const Icon(Icons.format_list_bulleted),
                        onPressed: () => _list('bullet'),
                      ),
                      IconButton(
                        tooltip: 'Lista numerada',
                        icon: const Icon(Icons.format_list_numbered),
                        onPressed: () => _list('number'),
                      ),
                      IconButton(
                        tooltip: 'Casillas ✓ (toca la casilla para marcarla)',
                        icon: const Icon(Icons.checklist),
                        onPressed: () => _list('check'),
                      ),
                      IconButton(
                        tooltip: 'Tarjeta de repaso con lo seleccionado',
                        icon: const Icon(Icons.style_outlined),
                        onPressed: () {
                          final sel = _controller.selection;
                          final picked = sel.isValid && !sel.isCollapsed
                              ? sel.textInside(_controller.text).trim()
                              : '';
                          showNewFlashcard(context, ref, back: picked);
                        },
                      ),
                      IconButton(
                        tooltip: 'Resaltador: selecciona texto y elige un color',
                        isSelected: _showMarker,
                        icon: const Icon(Icons.border_color),
                        onPressed: () => setState(() => _showMarker = !_showMarker),
                      ),
                    ],
                  ),
                ),
                if (_showMarker)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        IconButton(
                          tooltip: 'Quitar resaltado',
                          icon: const Icon(Icons.format_color_reset_outlined),
                          onPressed: () => _controller.highlightSelection(null),
                        ),
                        for (final c in highlighterColors)
                          GestureDetector(
                            onTap: () => _controller.highlightSelection(c),
                            child: Container(
                              width: 28,
                              height: 28,
                              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                              decoration: BoxDecoration(
                                color: Color(c),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.black12),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        TextField(
          controller: _controller,
          focusNode: _focus,
          onChanged: _onChanged,
          maxLines: null,
          autofocus: b.text.isEmpty,
          style: style,
          decoration: const InputDecoration(
            hintText: 'Escribe aquí…',
            border: InputBorder.none,
          ),
        ),
      ],
    );
  }
}
