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

  test('presupuesto: avisa al 80 % y al pasarse', () {
    String m(double v) => 'Bs ${v.toStringAsFixed(0)}';
    expect(budgetWarning(category: 'Carne', spentBefore: 100, spentAfter: 150, budget: 200, money: m), isNull);
    expect(budgetWarning(category: 'Carne', spentBefore: 150, spentAfter: 170, budget: 200, money: m),
        contains('Te quedan Bs 30'));
    expect(budgetWarning(category: 'Carne', spentBefore: 190, spentAfter: 230, budget: 200, money: m),
        contains('te pasaste Bs 30'));
    expect(budgetWarning(category: 'Carne', spentBefore: 0, spentAfter: 999, budget: null, money: m), isNull);
    expect(decodeBudgets(encodeBudgets({'Carne': 200, 'Pan': 0})), {'Carne': 200.0});
  });

  test('lista del súper adivina la categoría', () {
    expect(guessCategory('Tomates', defaultCategories), 'Verduras');
    expect(guessCategory('2 kg de pollo', defaultCategories), 'Carne');
    expect(guessCategory('Leche Pil', defaultCategories), 'Lácteos');
    expect(guessCategory('salchichas', defaultCategories), 'Carne');
    expect(guessCategory('cuaderno', defaultCategories), 'Otros');
    final l = [const ShoppingItem(id: '1', name: 'Arroz', category: 'Abarrotes', qty: '2 kg')];
    expect(ShoppingItem.decodeAll(ShoppingItem.encodeAll(l)).single.qty, '2 kg');
  });

  test('mes contra mes anterior', () {
    final now = [
      Expense(id: '1', day: DateTime(2026, 11, 3), category: 'Carne', amount: 100),
      Expense(id: '2', day: DateTime(2026, 11, 4), category: 'Pan', amount: 10),
    ];
    final before = [Expense(id: '3', day: DateTime(2026, 10, 3), category: 'Frutas', amount: 30)];
    final rows = compareMonths(now, before);
    expect(rows.first, ('Carne', 100.0, 0.0));
    expect(rows.last, ('Frutas', 0.0, 30.0));
    expect(previousMonth(DateTime(2026, 1, 15)).$1, DateTime(2025, 12, 1));
  });
}
