import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/expense.dart';

class ExpensesRepository {
  ExpensesRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Gastos con fecha en [from, to).
  Stream<List<Expense>> watchRange(DateTime from, DateTime to) {
    final q = _db.select(_db.expenses)
      ..where((e) => e.day.isBiggerOrEqualValue(from) & e.day.isSmallerThanValue(to))
      ..orderBy([(e) => OrderingTerm.desc(e.day), (e) => OrderingTerm.desc(e.createdAt)]);
    return q.watch().map((rows) => rows.map(_to).toList());
  }

  Future<void> save(Expense e) => _db.into(_db.expenses).insertOnConflictUpdate(ExpensesCompanion.insert(
        id: e.id.isEmpty ? _uuid.v4() : e.id,
        day: dayOnly(e.day),
        category: e.category,
        description: Value(e.description),
        amount: e.amount,
        createdAt: DateTime.now(),
      ));

  Future<void> delete(String id) => (_db.delete(_db.expenses)..where((e) => e.id.equals(id))).go();

  /// Cambia el nombre de una categoría en todos los gastos.
  Future<void> renameCategory(String from, String to) =>
      (_db.update(_db.expenses)..where((e) => e.category.equals(from)))
          .write(ExpensesCompanion(category: Value(to)));

  Expense _to(ExpenseRow r) => Expense(
        id: r.id,
        day: r.day,
        category: r.category,
        description: r.description,
        amount: r.amount,
      );
}
