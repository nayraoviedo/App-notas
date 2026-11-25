import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/fonts.dart';
import '../../../../core/providers.dart';
import '../../data/notes_repository.dart';
import '../../domain/note_block.dart';

/// Bloque de texto con fuente y tamaño propios. Guarda solo, medio segundo
/// después de dejar de escribir. Al tocarlo aparece la barra de fuente.
/// TODO: flutter_quill para negritas, listas y checklists.
class TextBlockView extends ConsumerStatefulWidget {
  const TextBlockView({super.key, required this.block});
  final TextBlock block;

  @override
  ConsumerState<TextBlockView> createState() => _TextBlockViewState();
}

class _TextBlockViewState extends ConsumerState<TextBlockView> {
  late final _controller = TextEditingController(text: widget.block.text);
  final _focus = FocusNode();
  Timer? _debounce;
  late final NotesRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(notesRepositoryProvider); // para usarlo también en dispose()
    _focus.addListener(() => setState(() {}));
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
    _controller.dispose();
    _focus.dispose();
    super.dispose();
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
    final style = fontStyle(b.fontFamily, size: b.fontSize, base: base);
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
