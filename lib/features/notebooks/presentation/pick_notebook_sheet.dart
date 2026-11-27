import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../domain/notebook.dart';

/// Lo que se eligió en [pickNotebookSheet]: un cuaderno o "sin cuaderno"
/// (id null). Si se cierra la hoja sin elegir, la función devuelve null.
class NotebookChoice {
  const NotebookChoice(this.notebookId);
  final String? notebookId;
}

/// Hoja para elegir en qué cuaderno guardar algo nuevo (por ejemplo una
/// grabación lanzada desde el widget). [suggestedId] sale arriba marcado
/// (el cuaderno de la clase que hay ahora) con [suggestedLabel] debajo.
Future<NotebookChoice?> pickNotebookSheet(
  BuildContext context,
  WidgetRef ref, {
  String title = '¿En qué cuaderno lo guardo?',
  String? suggestedId,
  String? suggestedLabel,
}) async {
  final List<Notebook> notebooks;
  try {
    notebooks = await ref.read(notebooksProvider.future);
  } catch (_) {
    return const NotebookChoice(null);
  }
  if (!context.mounted) return null;
  final suggested = notebooks.where((n) => n.id == suggestedId).firstOrNull;
  final rest = [for (final n in notebooks) if (n.id != suggested?.id) n];

  Widget tile(BuildContext context, Notebook nb, {String? subtitle}) => ListTile(
        leading: Icon(Icons.book, color: Color(nb.color)),
        title: Text(nb.name),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: subtitle == null ? null : const Icon(Icons.star_rounded, color: Color(0xFFE8B04A)),
        onTap: () => Navigator.pop(context, NotebookChoice(nb.id)),
      );

  return showModalBottomSheet<NotebookChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            if (suggested != null) tile(context, suggested, subtitle: suggestedLabel ?? 'Sugerido'),
            for (final nb in rest) tile(context, nb),
            ListTile(
              leading: const Icon(Icons.notes),
              title: const Text('Sin cuaderno'),
              subtitle: const Text('Queda en "Todas las notas"'),
              onTap: () => Navigator.pop(context, const NotebookChoice(null)),
            ),
          ],
        ),
      ),
    ),
  );
}
