import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
import '../domain/note.dart';

/// Busca en títulos, texto y en lo que se dijo en los audios.
class NotesSearchDelegate extends SearchDelegate<void> {
  NotesSearchDelegate(this.ref) : super(searchFieldLabel: 'Buscar en notas y audios');
  final WidgetRef ref;

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _results();

  @override
  Widget buildSuggestions(BuildContext context) =>
      query.length < 2 ? const SizedBox.shrink() : _results();

  Widget _results() => FutureBuilder<List<SearchHit>>(
        future: ref.read(notesRepositoryProvider).search(query),
        builder: (context, snap) {
          final hits = snap.data ?? const [];
          if (snap.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          if (hits.isEmpty) {
            return const Center(child: Text('Sin resultados'));
          }
          return ListView.builder(
            itemCount: hits.length,
            itemBuilder: (context, i) {
              final h = hits[i];
              return ListTile(
                leading: Icon(h.atMs != null ? Icons.graphic_eq : Icons.notes),
                title: Text(h.noteTitle.isEmpty ? 'Nota sin título' : h.noteTitle),
                subtitle: Text(h.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: h.atMs != null ? Text(formatMs(h.atMs!)) : null,
                onTap: () {
                  close(context, null);
                  context.push('/notes/${h.noteId}');
                },
              );
            },
          );
        },
      );
}
