import 'dart:convert';

/// Una compra del cuaderno "Gastos".
class Expense {
  const Expense({
    required this.id,
    required this.day,
    required this.category,
    required this.amount,
    this.description = '',
  });

  final String id;

  /// Día de la compra (sin hora).
  final DateTime day;
  final String category;
  final String description;
  final double amount;
}

/// Categoría de gasto (nombre, emoji y color).
class ExpenseCategory {
  const ExpenseCategory(this.name, this.emoji, this.color);
  final String name;
  final String emoji;
  final int color;

  Map<String, Object> toJson() => {'n': name, 'e': emoji, 'c': color};

  static ExpenseCategory fromJson(Map<String, Object?> j) =>
      ExpenseCategory(j['n'] as String, j['e'] as String? ?? '🛒', j['c'] as int? ?? 0xFFB0BEC5);

  static String encodeAll(List<ExpenseCategory> list) => jsonEncode([for (final c in list) c.toJson()]);

  static List<ExpenseCategory> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return defaultCategories;
    try {
      return [for (final j in jsonDecode(raw) as List) fromJson((j as Map).cast<String, Object?>())];
    } catch (_) {
      return defaultCategories;
    }
  }
}

const defaultCategories = <ExpenseCategory>[
  ExpenseCategory('Verduras', '🥬', 0xFF8BC34A),
  ExpenseCategory('Frutas', '🍎', 0xFFF48FB1),
  ExpenseCategory('Carne', '🥩', 0xFFE57373),
  ExpenseCategory('Abarrotes', '🍚', 0xFFFFCC80),
  ExpenseCategory('Lácteos', '🥛', 0xFF90CAF9),
  ExpenseCategory('Pan', '🍞', 0xFFD7B98E),
  ExpenseCategory('Limpieza', '🧼', 0xFF80DEEA),
  ExpenseCategory('Otros', '🛍️', 0xFFB39DDB),
];

/// Periodo para ver los gastos.
enum ExpensePeriod { day, week, month }

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Rango [inicio, fin) del periodo que contiene [ref]. La semana empieza el lunes.
(DateTime, DateTime) periodRange(ExpensePeriod p, DateTime ref) {
  final d = dayOnly(ref);
  return switch (p) {
    ExpensePeriod.day => (d, d.add(const Duration(days: 1))),
    ExpensePeriod.week => () {
        final start = d.subtract(Duration(days: d.weekday - 1));
        return (start, start.add(const Duration(days: 7)));
      }(),
    ExpensePeriod.month => (DateTime(d.year, d.month), DateTime(d.year, d.month + 1)),
  };
}

/// Totales por categoría, ordenados de mayor a menor.
List<(String, double)> totalsByCategory(Iterable<Expense> list) {
  final m = <String, double>{};
  for (final e in list) {
    m[e.category] = (m[e.category] ?? 0) + e.amount;
  }
  return m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
}

double totalOf(Iterable<Expense> list) => list.fold(0, (s, e) => s + e.amount);
