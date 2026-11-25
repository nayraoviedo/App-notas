import 'package:app_notas/features/expenses/domain/expense.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la semana va de lunes a domingo', () {
    final (a, b) = periodRange(ExpensePeriod.week, DateTime(2026, 11, 26, 15)); // jueves
    expect(a, DateTime(2026, 11, 23));
    expect(b, DateTime(2026, 11, 30));
  });

  test('el mes completo', () {
    final (a, b) = periodRange(ExpensePeriod.month, DateTime(2026, 12, 31));
    expect(a, DateTime(2026, 12));
    expect(b, DateTime(2027, 1));
  });

  test('totales por categoría ordenados', () {
    final list = [
      Expense(id: '1', day: DateTime(2026), category: 'Verduras', amount: 10),
      Expense(id: '2', day: DateTime(2026), category: 'Carne', amount: 40),
      Expense(id: '3', day: DateTime(2026), category: 'Verduras', amount: 5.5),
    ];
    final t = totalsByCategory(list);
    expect(t.first, ('Carne', 40.0));
    expect(t[1], ('Verduras', 15.5));
    expect(totalOf(list), 55.5);
  });

  test('categorías se guardan y se leen', () {
    final back = ExpenseCategory.decodeAll(ExpenseCategory.encodeAll(defaultCategories));
    expect(back.length, defaultCategories.length);
    expect(back.first.name, 'Verduras');
    expect(ExpenseCategory.decodeAll('basura').length, defaultCategories.length);
  });
}
