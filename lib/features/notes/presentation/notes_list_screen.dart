import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
import '../domain/note.dart';

class NotesListScreen extends ConsumerWidget {
  const NotesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis notas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar (también dentro de los audios)',
            onPressed: () => showSearch(
              context: context,
              delegate: _NotesSearchDelegate(ref),
            ),
          ),
        ],
      ),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _NoteTile(note: list[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nueva nota'),
        onPressed: () async {
          final id = await ref.read(notesRepositoryProvider).createNote();
          if (context.mounted) context.go('/notes/$id');
        },
      ),
    );
  }
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = note.updatedAt;
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => ref.read(notesRepositoryProvider).deleteNote(note.id),
      child: ListTile(
        title: Text(note.displayTitle),
        subtitle: Text(
          '${d.day}/${d.month}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
        ),
        onTap: () => context.go('/notes/${note.id}'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Todavía no tienes notas.\nCrea una y graba, escribe o toma fotos.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _NotesSearchDelegate extends SearchDelegate<void> {
  _NotesSearchDelegate(this.ref) : super(searchFieldLabel: 'Buscar en notas y audios');
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
                  context.go('/notes/${h.noteId}');
                },
              );
            },
          );
        },
      );
}
