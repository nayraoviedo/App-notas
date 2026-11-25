class Note {
  const Note({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.notebookId,
    this.tags = const [],
  });

  final String id;

  /// Etiquetas (#clase, #ideas…).
  final List<String> tags;
  final String title;
  final String? notebookId;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayTitle => title.trim().isEmpty ? 'Nota sin título' : title;
}

/// Resultado de búsqueda: puede apuntar a un minuto exacto de un audio.
class SearchHit {
  const SearchHit({
    required this.noteId,
    required this.noteTitle,
    required this.snippet,
    this.blockId,
    this.atMs,
  });

  final String noteId;
  final String noteTitle;
  final String snippet;
  final String? blockId;
  final int? atMs;
}
