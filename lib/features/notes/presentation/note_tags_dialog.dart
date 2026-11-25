import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/cat_mascot.dart';

/// Etiquetas de una nota (como "Etiqueta" en StarNote).
Future<void> showNoteTagsDialog(BuildContext context, WidgetRef ref, String noteId) async {
  final note = ref.read(noteProvider(noteId)).valueOrNull ??
      await ref.read(notesRepositoryProvider).watchNote(noteId).first;
  if (note == null || !context.mounted) return;
  final result = await showTagPicker(context, initial: note.tags);
  if (result != null) await ref.read(notesRepositoryProvider).setTags(noteId, result);
}

/// Elegir etiquetas. Devuelve la selección, o null si se canceló.
Future<List<String>?> showTagPicker(BuildContext context, {List<String> initial = const []}) =>
    showDialog<List<String>>(
      context: context,
      builder: (_) => _TagPicker(initial: initial),
    );

class _TagPicker extends ConsumerStatefulWidget {
  const _TagPicker({required this.initial});
  final List<String> initial;

  @override
  ConsumerState<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends ConsumerState<_TagPicker> {
  late final Set<String> _selected = {...widget.initial};
  final _search = TextEditingController();
  final _extra = <String>{}; // creadas ahora, aún sin guardar

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final ctl = TextEditingController(text: _search.text.trim());
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva etiqueta'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(prefixText: '# ', hintText: 'clase, ideas, viaje…'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('Agregar')),
        ],
      ),
    );
    final t = name?.replaceAll('#', '').replaceAll('|', ' ').trim() ?? '';
    if (t.isEmpty) return;
    setState(() {
      _extra.add(t);
      _selected.add(t);
      _search.clear();
    });
  }

  Future<void> _manage(List<String> all) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Gestionar etiquetas')),
            for (final t in all)
              ListTile(
                leading: const Icon(Icons.tag),
                title: Text(t),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Renombrar',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final ctl = TextEditingController(text: t);
                        final to = await showDialog<String>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Renombrar etiqueta'),
                            content: TextField(controller: ctl, autofocus: true),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancelar')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(context, ctl.text),
                                  child: const Text('Guardar')),
                            ],
                          ),
                        );
                        if (to == null || to.trim().isEmpty) return;
                        await ref.read(notesRepositoryProvider).renameTag(t, to);
                        if (_selected.remove(t)) _selected.add(to.trim());
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                    IconButton(
                      tooltip: 'Quitar de todas las notas',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await ref.read(notesRepositoryProvider).renameTag(t, null);
                        _selected.remove(t);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final saved = ref.watch(allTagsProvider).valueOrNull ?? const <String>[];
    final all = {...saved, ..._extra, ..._selected}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty ? all : all.where((t) => t.toLowerCase().contains(q)).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                  Expanded(
                    child: Text('Etiqueta',
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _selected.toList()),
                    child: const Text('Hecho'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar etiqueta',
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Agregar nueva etiqueta'),
                ),
              ),
              Flexible(
                child: shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CatMascot(kind: CatKind.gray, size: 110),
                            const SizedBox(height: 12),
                            Text(
                              all.isEmpty
                                  ? '¡Todavía no tienes etiquetas!\n¡Vamos a crear una!'
                                  : 'No hay etiquetas con ese nombre',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final t in shown)
                            CheckboxListTile(
                              value: _selected.contains(t),
                              title: Text('# $t'),
                              onChanged: (v) => setState(() {
                                v == true ? _selected.add(t) : _selected.remove(t);
                              }),
                            ),
                        ],
                      ),
              ),
              TextButton(
                onPressed: saved.isEmpty ? null : () => _manage(saved),
                child: const Text('Gestionar etiquetas'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
