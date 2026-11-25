import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../domain/note_block.dart';

/// Bloque de texto. Guarda solo, medio segundo después de dejar de escribir.
/// TODO: cambiar por flutter_quill para negritas, listas y checklists.
class TextBlockView extends ConsumerStatefulWidget {
  const TextBlockView({super.key, required this.block});
  final TextBlock block;

  @override
  ConsumerState<TextBlockView> createState() => _TextBlockViewState();
}

class _TextBlockViewState extends ConsumerState<TextBlockView> {
  late final _controller = TextEditingController(text: widget.block.text);
  Timer? _debounce;
  late final _repo = ref.read(notesRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _repo; // se lee aquí para poder usarlo con seguridad en dispose()
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        onChanged: _onChanged,
        maxLines: null,
        autofocus: widget.block.text.isEmpty,
        decoration: const InputDecoration(
          hintText: 'Escribe aquí…',
          border: InputBorder.none,
        ),
      );
}
