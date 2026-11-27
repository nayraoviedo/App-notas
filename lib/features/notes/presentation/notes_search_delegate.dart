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
                leading: Icon(h.inTranscript
                    ? Icons.graphic_eq
                    : h.snippet.startsWith('✍️')
                        ? Icons.draw_outlined
                        : Icons.notes),
                title: Text(h.noteTitle.isEmpty ? 'Nota sin título' : h.noteTitle),
                subtitle: _highlight(context, _around(h.snippet, query)),
                trailing: h.inTranscript && h.atMs != null
                    ? Chip(
                        avatar: const Icon(Icons.play_arrow, size: 16),
                        label: Text(formatMs(h.atMs!)),
                        visualDensity: VisualDensity.compact,
                      )
                    : null,
                onTap: () {
                  close(context, null);
                  // Lo que dijo el profe: abrir la grabación en ese minuto.
                  if (h.inTranscript && h.blockId != null) {
                    context.push('/notes/${h.noteId}/audio/${h.blockId}?t=${h.atMs ?? 0}');
                  } else {
                    context.push('/notes/${h.noteId}');
                  }
                },
              );
            },
          );
        },
      );

  /// Un pedazo del texto alrededor de lo buscado.
  static String _around(String text, String q) {
    final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final i = t.toLowerCase().indexOf(q.trim().toLowerCase());
    if (i < 0 || t.length <= 140) return t;
    final start = (i - 50).clamp(0, t.length);
    final end = (i + q.length + 80).clamp(0, t.length);
    return '${start > 0 ? '…' : ''}${t.substring(start, end)}${end < t.length ? '…' : ''}';
  }

  /// Resalta lo buscado en amarillo.
  Widget _highlight(BuildContext context, String text) {
    final q = query.trim().toLowerCase();
    final style = DefaultTextStyle.of(context).style;
    if (q.isEmpty) return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis);
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    var from = 0;
    while (true) {
      final i = lower.indexOf(q, from);
      if (i < 0) break;
      if (i > from) spans.add(TextSpan(text: text.substring(from, i)));
      spans.add(TextSpan(
        text: text.substring(i, i + q.length),
        style: const TextStyle(backgroundColor: Color(0xFFFFF176), fontWeight: FontWeight.w600),
      ));
      from = i + q.length;
    }
    if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
    return Text.rich(TextSpan(style: style, children: spans), maxLines: 3, overflow: TextOverflow.ellipsis);
  }
}
