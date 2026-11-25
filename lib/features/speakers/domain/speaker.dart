class Speaker {
  const Speaker({required this.id, required this.name, this.embedding});

  final String id;
  final String name;

  /// Huella de voz guardada (null si aún no se ha aprendido).
  final List<double>? embedding;
}

/// Desde [atMs] habla la persona [speakerId].
class SpeakerTurn {
  const SpeakerTurn({required this.atMs, required this.speakerId});

  final int atMs;
  final String speakerId;
}

/// La app detectó un posible cambio de voz y le pregunta al usuario.
class SpeakerChangeSuggestion {
  const SpeakerChangeSuggestion({
    required this.atMs,
    required this.embedding,
    this.likelySpeakerId,
  });

  final int atMs;
  final List<double> embedding;

  /// Si la voz se parece a alguien conocido, se sugiere esa persona.
  final String? likelySpeakerId;
}
