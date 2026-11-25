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

// ------------------------------------------------------------ Presupuestos

/// Presupuesto mensual por categoría ("Carne" → 200).
Map<String, double> decodeBudgets(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    return {
      for (final e in (jsonDecode(raw) as Map).entries)
        if ((e.value as num) > 0) e.key as String: (e.value as num).toDouble(),
    };
  } catch (_) {
    return const {};
  }
}

String encodeBudgets(Map<String, double> b) => jsonEncode(b);

/// Aviso para mostrar después de anotar un gasto, o null si va bien.
/// Avisa al llegar al 80 % y al pasarse.
String? budgetWarning({
  required String category,
  required double spentBefore,
  required double spentAfter,
  required double? budget,
  required String Function(double) money,
}) {
  if (budget == null || budget <= 0) return null;
  if (spentAfter > budget) {
    return '⚠️ $category: ya gastaste ${money(spentAfter)} de ${money(budget)} este mes '
        '(te pasaste ${money(spentAfter - budget)}).';
  }
  if (spentAfter >= budget * 0.8 && spentBefore < budget * 0.8) {
    return '👀 $category: vas ${money(spentAfter)} de ${money(budget)} este mes. '
        'Te quedan ${money(budget - spentAfter)}.';
  }
  return null;
}

// ---------------------------------------------------------- Lista del súper

class ShoppingItem {
  const ShoppingItem({required this.id, required this.name, required this.category, this.qty = ''});
  final String id;
  final String name;
  final String category;
  final String qty;

  Map<String, Object> toJson() => {'id': id, 'n': name, 'c': category, if (qty.isNotEmpty) 'q': qty};

  static ShoppingItem fromJson(Map<String, Object?> j) => ShoppingItem(
        id: j['id'] as String,
        name: j['n'] as String? ?? '',
        category: j['c'] as String? ?? 'Otros',
        qty: j['q'] as String? ?? '',
      );

  static String encodeAll(List<ShoppingItem> l) => jsonEncode([for (final i in l) i.toJson()]);

  static List<ShoppingItem> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [for (final j in jsonDecode(raw) as List) fromJson((j as Map).cast<String, Object?>())];
    } catch (_) {
      return const [];
    }
  }
}

// ------------------------------------------------ Mes contra mes anterior

/// Rango del mes anterior al de [ref].
(DateTime, DateTime) previousMonth(DateTime ref) =>
    (DateTime(ref.year, ref.month - 1, 1), DateTime(ref.year, ref.month, 1));

/// Para cada categoría (de los dos meses): (nombre, este mes, mes anterior),
/// de mayor a menor gasto actual.
List<(String, double, double)> compareMonths(Iterable<Expense> current, Iterable<Expense> previous) {
  final a = {for (final (n, v) in totalsByCategory(current)) n: v};
  final b = {for (final (n, v) in totalsByCategory(previous)) n: v};
  final names = {...a.keys, ...b.keys}.toList()
    ..sort((x, y) => (a[y] ?? 0).compareTo(a[x] ?? 0) != 0
        ? (a[y] ?? 0).compareTo(a[x] ?? 0)
        : (b[y] ?? 0).compareTo(b[x] ?? 0));
  return [for (final n in names) (n, a[n] ?? 0, b[n] ?? 0)];
}

/// Adivina la categoría por el nombre ("tomate" → Verduras). Si no sabe,
/// la última categoría (normalmente "Otros").
String guessCategory(String item, List<ExpenseCategory> cats) {
  const words = {
    'Verduras': ['tomate', 'cebolla', 'papa', 'zanahoria', 'lechuga', 'locoto', 'ajo', 'brócoli', 'brocoli',
      'zapallo', 'pepino', 'choclo', 'arveja', 'haba', 'perejil', 'apio', 'espinaca', 'pimentón', 'repollo',
      'vainita', 'remolacha', 'acelga', 'verdura'],
    'Frutas': ['manzana', 'plátano', 'platano', 'banana', 'naranja', 'mandarina', 'uva', 'pera', 'papaya',
      'piña', 'sandía', 'sandia', 'frutilla', 'durazno', 'limón', 'limon', 'mango', 'fruta', 'palta', 'kiwi'],
    'Carne': ['pollo', 'carne', 'res', 'cerdo', 'chancho', 'pescado', 'chorizo', 'salchicha', 'molida',
      'costilla', 'pechuga', 'jamón', 'jamon', 'trucha', 'charque'],
    'Lácteos': ['leche', 'queso', 'yogur', 'yogurt', 'mantequilla', 'crema', 'huevo'],
    'Pan': ['pan', 'marraqueta', 'galleta', 'torta', 'sarnita'],
    'Abarrotes': ['arroz', 'fideo', 'azúcar', 'azucar', 'aceite', 'sal', 'harina', 'café', 'cafe', 'té',
      'avena', 'atún', 'atun', 'lenteja', 'quinua', 'mayonesa', 'salsa'],
    'Limpieza': ['detergente', 'jabón', 'jabon', 'lavandina', 'papel', 'shampoo', 'champú', 'esponja',
      'cloro', 'escoba', 'pasta dental'],
  };
  final t = item.toLowerCase();
  final names = {for (final c in cats) c.name};
  for (final e in words.entries) {
    if (names.contains(e.key) && e.value.any((w) => RegExp('(^|\\W)$w').hasMatch(t))) return e.key;
  }
  return cats.isEmpty ? 'Otros' : (names.contains('Otros') ? 'Otros' : cats.last.name);
}
