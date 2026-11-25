/// Tarjeta de repaso: pregunta (frente) y respuesta (reverso).
class Flashcard {
  const Flashcard({
    required this.id,
    required this.front,
    required this.back,
    required this.due,
    this.noteId,
    this.deck = 'General',
    this.intervalDays = 0,
    this.ease = 2.5,
    this.reps = 0,
  });

  final String id;
  final String front;
  final String back;
  final String? noteId;
  final String deck;

  /// Cuándo toca repasarla.
  final DateTime due;
  final int intervalDays;
  final double ease;
  final int reps;

  Flashcard copyWith({String? front, String? back, String? deck, DateTime? due, int? intervalDays, double? ease, int? reps}) =>
      Flashcard(
        id: id,
        front: front ?? this.front,
        back: back ?? this.back,
        noteId: noteId,
        deck: deck ?? this.deck,
        due: due ?? this.due,
        intervalDays: intervalDays ?? this.intervalDays,
        ease: ease ?? this.ease,
        reps: reps ?? this.reps,
      );
}

/// Qué tan bien se recordó.
enum Recall {
  again('Otra vez'),
  hard('Difícil'),
  good('Bien'),
  easy('Fácil');

  const Recall(this.label);
  final String label;
}

/// Repaso espaciado (SM-2 simplificado, como Anki): cada vez que se recuerda
/// bien, el siguiente repaso es más tarde (1 día, 3 días, ~1 semana…).
Flashcard schedule(Flashcard c, Recall r, {DateTime? now}) {
  final today = now ?? DateTime.now();
  var ease = c.ease;
  int interval;
  var reps = c.reps;
  switch (r) {
    case Recall.again:
      reps = 0;
      interval = 0;
      ease = (ease - 0.2).clamp(1.3, 3.0);
    case Recall.hard:
      reps += 1;
      interval = c.intervalDays <= 1 ? 1 : (c.intervalDays * 1.2).round();
      ease = (ease - 0.15).clamp(1.3, 3.0);
    case Recall.good:
      reps += 1;
      interval = reps == 1 ? 1 : (reps == 2 ? 3 : (c.intervalDays * ease).round());
    case Recall.easy:
      reps += 1;
      interval = reps == 1 ? 3 : ((c.intervalDays == 0 ? 3 : c.intervalDays) * ease * 1.3).round();
      ease = (ease + 0.15).clamp(1.3, 3.0);
  }
  final due = interval == 0
      ? today.add(const Duration(minutes: 10))
      : DateTime(today.year, today.month, today.day).add(Duration(days: interval));
  return c.copyWith(due: due, intervalDays: interval, ease: ease, reps: reps);
}

/// Texto corto del próximo repaso ("en 3 días").
String nextLabel(Flashcard c, Recall r) {
  final n = schedule(c, r);
  if (n.intervalDays == 0) return '10 min';
  if (n.intervalDays == 1) return '1 día';
  if (n.intervalDays < 30) return '${n.intervalDays} días';
  return '${(n.intervalDays / 30).round()} mes';
}
