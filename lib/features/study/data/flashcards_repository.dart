import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/flashcard.dart';

class FlashcardsRepository {
  FlashcardsRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Flashcard>> watchAll() =>
      (_db.select(_db.flashcards)..orderBy([(f) => OrderingTerm.asc(f.due)])).watch().map((r) => r.map(_to).toList());

  Future<String> add({required String front, required String back, String? noteId, String deck = 'General'}) async {
    final id = _uuid.v4();
    await _db.into(_db.flashcards).insert(FlashcardsCompanion.insert(
          id: id,
          front: front,
          back: back,
          noteId: Value(noteId),
          deck: Value(deck),
          due: DateTime.now(),
          createdAt: DateTime.now(),
        ));
    return id;
  }

  Future<void> save(Flashcard c) => (_db.update(_db.flashcards)..where((f) => f.id.equals(c.id))).write(
        FlashcardsCompanion(
          front: Value(c.front),
          back: Value(c.back),
          deck: Value(c.deck),
          due: Value(c.due),
          intervalDays: Value(c.intervalDays),
          ease: Value(c.ease),
          reps: Value(c.reps),
        ),
      );

  Future<void> delete(String id) => (_db.delete(_db.flashcards)..where((f) => f.id.equals(id))).go();

  Flashcard _to(FlashcardRow r) => Flashcard(
        id: r.id,
        front: r.front,
        back: r.back,
        noteId: r.noteId,
        deck: r.deck,
        due: r.due,
        intervalDays: r.intervalDays,
        ease: r.ease,
        reps: r.reps,
      );
}
