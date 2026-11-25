import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/notebook.dart';

class NotebooksRepository {
  NotebooksRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Notebook>> watchAll() => (_db.select(_db.notebooks)
        ..orderBy([(n) => OrderingTerm.asc(n.createdAt)]))
      .watch()
      .map((rows) => rows.map(_toNotebook).toList());

  Stream<Notebook?> watch(String id) =>
      (_db.select(_db.notebooks)..where((n) => n.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r == null ? null : _toNotebook(r));

  /// Cantidad de notas por cuaderno (para mostrar en la portada).
  Stream<Map<String, int>> watchCounts() {
    final count = _db.notes.id.count();
    final q = _db.selectOnly(_db.notes)
      ..addColumns([_db.notes.notebookId, count])
      ..groupBy([_db.notes.notebookId]);
    return q.watch().map((rows) => {
          for (final r in rows)
            if (r.read(_db.notes.notebookId) != null)
              r.read(_db.notes.notebookId)!: r.read(count) ?? 0,
        });
  }

  Future<String> create(String name, {required int color, String? coverPath}) async {
    final id = _uuid.v4();
    await _db.into(_db.notebooks).insert(NotebooksCompanion.insert(
          id: id,
          name: name,
          color: Value(color),
          coverPath: Value(coverPath),
          createdAt: DateTime.now(),
        ));
    return id;
  }

  Future<void> update(String id, {required String name, required int color, String? coverPath}) =>
      (_db.update(_db.notebooks)..where((n) => n.id.equals(id))).write(
        NotebooksCompanion(
          name: Value(name),
          color: Value(color),
          coverPath: Value(coverPath),
        ),
      );

  /// Borra el cuaderno; sus notas quedan "sin cuaderno" (no se pierden).
  Future<void> delete(String id) => _db.transaction(() async {
        await (_db.update(_db.notes)..where((n) => n.notebookId.equals(id)))
            .write(const NotesCompanion(notebookId: Value(null)));
        await (_db.delete(_db.notebooks)..where((n) => n.id.equals(id))).go();
      });

  Notebook _toNotebook(NotebookRow r) =>
      Notebook(id: r.id, name: r.name, color: r.color, coverPath: r.coverPath);
}
