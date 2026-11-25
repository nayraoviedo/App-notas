import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/fonts.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/cat_mascot.dart';
import '../../settings/settings.dart';
import '../domain/expense.dart';

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _monthsLong = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
const _weekdaysLong = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

String _fmtDay(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// Categorías guardadas (se pueden agregar y quitar).
final expenseCategoriesProvider = StateProvider<List<ExpenseCategory>>(
  (ref) => ExpenseCategory.decodeAll(ref.watch(sharedPreferencesProvider).getString('expenses.categories')),
);

/// Moneda (por defecto bolivianos).
final currencyProvider = StateProvider<String>(
    (ref) => ref.watch(sharedPreferencesProvider).getString('expenses.currency') ?? 'Bs');

/// Presupuesto mensual por categoría.
final budgetsProvider = StateProvider<Map<String, double>>(
    (ref) => decodeBudgets(ref.watch(sharedPreferencesProvider).getString('expenses.budgets')));

/// Lista del súper (lo que falta comprar).
final shoppingProvider = StateProvider<List<ShoppingItem>>(
    (ref) => ShoppingItem.decodeAll(ref.watch(sharedPreferencesProvider).getString('expenses.shopping')));

final _rangeProvider =
    StreamProvider.autoDispose.family<List<Expense>, (DateTime, DateTime)>((ref, r) => ref.watch(expensesRepositoryProvider).watchRange(r.$1, r.$2));

/// Cuaderno "Gastos": compras por categoría con totales del día, la semana y
/// el mes.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  ExpensePeriod _period = ExpensePeriod.week;
  DateTime _ref = DateTime.now();

  String _money(double v) {
    final cur = ref.read(currencyProvider);
    final txt = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return '$cur $txt';
  }

  void _shift(int dir) {
    setState(() {
      _ref = switch (_period) {
        ExpensePeriod.day => _ref.add(Duration(days: dir)),
        ExpensePeriod.week => _ref.add(Duration(days: 7 * dir)),
        ExpensePeriod.month => DateTime(_ref.year, _ref.month + dir, 1),
      };
    });
  }

  String _periodLabel((DateTime, DateTime) r) => switch (_period) {
        ExpensePeriod.day => '${_weekdaysLong[r.$1.weekday - 1]} ${_fmtDay(r.$1)}',
        ExpensePeriod.week => '${_fmtDay(r.$1)} – ${_fmtDay(r.$2.subtract(const Duration(days: 1)))}',
        ExpensePeriod.month => '${_months[r.$1.month - 1].toUpperCase()} ${r.$1.year}',
      };

  @override
  Widget build(BuildContext context) {
    final range = periodRange(_period, _ref);
    final list = ref.watch(_rangeProvider(range)).valueOrNull ?? const <Expense>[];
    final cats = {for (final c in ref.watch(expenseCategoriesProvider)) c.name: c};
    final totals = totalsByCategory(list);
    final total = totalOf(list);
    final monthRange = periodRange(ExpensePeriod.month, _ref);
    final monthList = ref.watch(_rangeProvider(monthRange)).valueOrNull ?? const <Expense>[];
    final prevList = _period == ExpensePeriod.month
        ? ref.watch(_rangeProvider(previousMonth(_ref))).valueOrNull ?? const <Expense>[]
        : const <Expense>[];
    final budgets = ref.watch(budgetsProvider);
    final shopping = ref.watch(shoppingProvider);

    // Agrupar por día.
    final byDay = <DateTime, List<Expense>>{};
    for (final e in list) {
      byDay.putIfAbsent(dayOnly(e.day), () => []).add(e);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9F2),
        title: Text('Gastos', style: fontStyle('Pacifico', size: 24)),
        actions: [
          IconButton(
            tooltip: 'Lista del súper',
            icon: Badge(
              isLabelVisible: shopping.isNotEmpty,
              label: Text('${shopping.length}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            onPressed: _shoppingList,
          ),
          IconButton(
            tooltip: 'Compartir resumen',
            icon: const Icon(Icons.ios_share),
            onPressed: () => _shareSummary(range, list, totals, total),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'cats') _editCategories();
              if (v == 'cur') _editCurrency();
              if (v == 'budget') _editBudgets();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'budget', child: Text('Presupuesto del mes')),
              PopupMenuItem(value: 'cats', child: Text('Categorías')),
              PopupMenuItem(value: 'cur', child: Text('Moneda')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF7FB069),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Gasto'),
        onPressed: () => _edit(null, day: _period == ExpensePeriod.day ? range.$1 : DateTime.now()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          SegmentedButton<ExpensePeriod>(
            segments: const [
              ButtonSegment(value: ExpensePeriod.day, label: Text('Día')),
              ButtonSegment(value: ExpensePeriod.week, label: Text('Semana')),
              ButtonSegment(value: ExpensePeriod.month, label: Text('Mes')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _ref = DateTime.now()),
                  child: Text(_periodLabel(range),
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
            ],
          ),
          // Total del periodo y por categoría.
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('Total', style: TextStyle(color: Colors.black54)),
                      const Spacer(),
                      Text(_money(total),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  if (_period == ExpensePeriod.week) ...[
                    const SizedBox(height: 12),
                    _WeekBars(start: range.$1, list: list),
                  ],
                  const SizedBox(height: 8),
                  if (totals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CatMascot(kind: CatKind.orange, size: 56),
                          SizedBox(width: 12),
                          Flexible(child: Text('Todavía no hay gastos aquí.\nToca "+ Gasto" para anotar una compra.')),
                        ],
                      ),
                    ),
                  for (final (name, value) in totals)
                    _CategoryRow(
                      category: cats[name] ?? ExpenseCategory(name, '🛒', 0xFFB0BEC5),
                      amount: _money(value),
                      fraction: total == 0 ? 0 : value / total,
                    ),
                ],
              ),
            ),
          ),
          if (budgets.isNotEmpty)
            _BudgetCard(
              budgets: budgets,
              spent: {for (final (n, v) in totalsByCategory(monthList)) n: v},
              cats: cats,
              money: _money,
              month: _months[monthRange.$1.month - 1],
              onEdit: _editBudgets,
            ),
          if (_period == ExpensePeriod.month && (list.isNotEmpty || prevList.isNotEmpty))
            _CompareCard(
              rows: compareMonths(list, prevList),
              total: total,
              prevTotal: totalOf(prevList),
              cats: cats,
              money: _money,
              prevName: _monthsLong[previousMonth(_ref).$1.month - 1],
            ),
          const SizedBox(height: 8),
          // Lista por día.
          for (final entry in byDay.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
              child: Row(
                children: [
                  Text('${_weekdaysLong[entry.key.weekday - 1]} ${_fmtDay(entry.key)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(_money(totalOf(entry.value)), style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            for (final e in entry.value)
              Dismissible(
                key: ValueKey(e.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red.shade100,
                  child: const Icon(Icons.delete_outline),
                ),
                onDismissed: (_) => ref.read(expensesRepositoryProvider).delete(e.id),
                child: Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 6),
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(cats[e.category]?.color ?? 0xFFB0BEC5).withValues(alpha: 0.3),
                      child: Text(cats[e.category]?.emoji ?? '🛒', style: const TextStyle(fontSize: 20)),
                    ),
                    title: Text(e.description.isEmpty ? e.category : e.description),
                    subtitle: e.description.isEmpty ? null : Text(e.category),
                    trailing: Text(_money(e.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () => _edit(e),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<bool> _edit(Expense? e, {DateTime? day, String? desc, String? category}) async {
    final result = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _ExpenseForm(initial: e, day: day ?? DateTime.now(), desc: desc, category: category),
      ),
    );
    if (result == null) return false;
    // Lo gastado este mes en la categoría, antes de guardar.
    final month = periodRange(ExpensePeriod.month, result.day);
    final before = ref.read(_rangeProvider(month)).valueOrNull;
    await ref.read(expensesRepositoryProvider).save(result);
    if (before != null && mounted) {
      final spent = before
          .where((x) => x.category == result.category && x.id != result.id)
          .fold<double>(0, (a, x) => a + x.amount);
      final msg = budgetWarning(
        category: result.category,
        spentBefore: spent,
        spentAfter: spent + result.amount,
        budget: ref.read(budgetsProvider)[result.category],
        money: _money,
      );
      if (msg != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 6),
          backgroundColor: msg.startsWith('⚠️') ? Colors.red.shade700 : null,
        ));
      }
    }
    return true;
  }

  Future<void> _editBudgets() async {
    final cats = ref.read(expenseCategoriesProvider);
    final current = ref.read(budgetsProvider);
    final ctls = {
      for (final c in cats)
        c.name: TextEditingController(
            text: current[c.name] == null ? '' : current[c.name]!.toStringAsFixed(0)),
    };
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Presupuesto del mes', style: Theme.of(context).textTheme.titleMedium),
              const Text('Cuánto quieres gastar como máximo en cada categoría. '
                  'Te aviso al llegar al 80 % y si te pasas. Deja vacío para no poner límite.',
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              for (final c in cats)
                TextField(
                  controller: ctls[c.name],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '${c.emoji} ${c.name}',
                    prefixText: '${ref.read(currencyProvider)} ',
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7FB069)),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    final b = <String, double>{
      for (final e in ctls.entries)
        if (double.tryParse(e.value.text.replaceAll(',', '.').trim()) case final v? when v > 0) e.key: v,
    };
    await ref.read(sharedPreferencesProvider).setString('expenses.budgets', encodeBudgets(b));
    ref.read(budgetsProvider.notifier).state = b;
  }

  Future<void> _shoppingList() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ShoppingSheet(
        onBought: (item) async {
          // Comprado: se anota como gasto con lo que costó.
          final saved = await _edit(null, desc: item.name + (item.qty.isEmpty ? '' : ' (${item.qty})'),
              category: item.category);
          return saved;
        },
      ),
    );
  }

  Future<void> _editCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _CategoriesSheet(),
    );
  }

  Future<void> _editCurrency() async {
    final ctl = TextEditingController(text: ref.read(currencyProvider));
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Moneda'),
        content: TextField(controller: ctl, decoration: const InputDecoration(hintText: 'Bs, \$, S/, €…')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    await ref.read(sharedPreferencesProvider).setString('expenses.currency', v);
    ref.read(currencyProvider.notifier).state = v;
  }

  Future<void> _shareSummary(
      (DateTime, DateTime) range, List<Expense> list, List<(String, double)> totals, double total) async {
    final b = StringBuffer('🧾 Gastos · ${_periodLabel(range)}\n');
    for (final (name, v) in totals) {
      b.writeln('• $name: ${_money(v)}');
    }
    b.writeln('Total: ${_money(total)}');
    await Clipboard.setData(ClipboardData(text: b.toString()));
    await SharePlus.instance.share(ShareParams(text: b.toString()));
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.amount, required this.fraction});
  final ExpenseCategory category;
  final String amount;
  final double fraction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('${category.emoji}  ${category.name}'),
                const Spacer(),
                Text(amount, style: const TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(
                  width: 44,
                  child: Text('${(fraction * 100).round()}%',
                      textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.black45)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: Color(category.color).withValues(alpha: 0.15),
                color: Color(category.color),
              ),
            ),
          ],
        ),
      );
}

/// Barritas con el total de cada día de la semana.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.start, required this.list});
  final DateTime start;
  final List<Expense> list;

  @override
  Widget build(BuildContext context) {
    final totals = List<double>.filled(7, 0);
    for (final e in list) {
      final i = dayOnly(e.day).difference(start).inDays;
      if (i >= 0 && i < 7) totals[i] += e.amount;
    }
    final maxV = totals.fold<double>(0, math.max);
    final today = dayOnly(DateTime.now());
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (totals[i] > 0)
                    Text(totals[i].toStringAsFixed(0), style: const TextStyle(fontSize: 10, color: Colors.black54)),
                  const SizedBox(height: 2),
                  Container(
                    height: maxV == 0 ? 4 : math.max(4, 70 * totals[i] / maxV),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: start.add(Duration(days: i)) == today ? const Color(0xFF7FB069) : const Color(0xFFC5E1A5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_weekdays[i], style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm({this.initial, required this.day, this.desc, this.category});
  final Expense? initial;
  final DateTime day;

  /// Para anotar algo de la lista del súper.
  final String? desc;
  final String? category;

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  late final _amount = TextEditingController(
      text: widget.initial == null ? '' : widget.initial!.amount.toStringAsFixed(2).replaceAll('.00', ''));
  late final _desc = TextEditingController(text: widget.initial?.description ?? widget.desc ?? '');
  late DateTime _day = widget.initial?.day ?? widget.day;
  late String? _cat = widget.initial?.category ?? widget.category;

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_amount.text.replaceAll(',', '.').trim());

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(expenseCategoriesProvider);
    final cur = ref.watch(currencyProvider);
    _cat ??= cats.first.name;
    final ok = (_value ?? 0) > 0 && _cat != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.initial == null ? (widget.desc != null ? '¿Cuánto costó?' : 'Nuevo gasto') : 'Editar gasto',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: widget.initial == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              decoration: InputDecoration(prefixText: '$cur ', hintText: '0'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in cats)
                  ChoiceChip(
                    avatar: Text(c.emoji),
                    label: Text(c.name),
                    selected: _cat == c.name,
                    selectedColor: Color(c.color).withValues(alpha: 0.35),
                    onSelected: (_) => setState(() => _cat = c.name),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: '¿Qué compraste? (opcional)',
                hintText: 'Tomates, cebolla, pollo…',
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text('${_weekdaysLong[_day.weekday - 1]} ${_fmtDay(_day)} ${_day.year}'),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _day,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _day = d);
              },
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7FB069)),
              onPressed: !ok
                  ? null
                  : () => Navigator.pop(
                        context,
                        Expense(
                          id: widget.initial?.id ?? '',
                          day: _day,
                          category: _cat!,
                          amount: _value!,
                          description: _desc.text.trim(),
                        ),
                      ),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoriesSheet extends ConsumerWidget {
  const _CategoriesSheet();

  static const _emojis = ['🥬', '🍎', '🥩', '🍚', '🥛', '🍞', '🧼', '🛍️', '🐟', '🥚', '🧃', '🍬', '🐱', '💊', '🚌', '🏠', '📚', '🎁'];
  static const _colors = [0xFF8BC34A, 0xFFF48FB1, 0xFFE57373, 0xFFFFCC80, 0xFF90CAF9, 0xFFD7B98E, 0xFF80DEEA, 0xFFB39DDB];

  Future<void> _save(WidgetRef ref, List<ExpenseCategory> list) async {
    await ref.read(sharedPreferencesProvider).setString('expenses.categories', ExpenseCategory.encodeAll(list));
    ref.read(expenseCategoriesProvider.notifier).state = list;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(expenseCategoriesProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            const ListTile(title: Text('Categorías'), subtitle: Text('Mantén presionada una para quitarla')),
            Expanded(
              child: ListView(
                children: [
                  for (final c in cats)
                    ListTile(
                      leading: Text(c.emoji, style: const TextStyle(fontSize: 24)),
                      title: Text(c.name),
                      trailing: CircleAvatar(radius: 8, backgroundColor: Color(c.color)),
                      onLongPress: cats.length <= 1
                          ? null
                          : () => _save(ref, [for (final x in cats) if (x.name != c.name) x]),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Nueva categoría'),
                onPressed: () async {
                  final ctl = TextEditingController();
                  var emoji = _emojis.first;
                  final name = await showDialog<String>(
                    context: context,
                    builder: (context) => StatefulBuilder(
                      builder: (context, setState) => AlertDialog(
                        title: const Text('Nueva categoría'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: ctl,
                              autofocus: true,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(hintText: 'Pescado, Bebidas…'),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 4,
                              children: [
                                for (final e in _emojis)
                                  ChoiceChip(
                                    label: Text(e),
                                    selected: e == emoji,
                                    onSelected: (_) => setState(() => emoji = e),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                          FilledButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('Agregar')),
                        ],
                      ),
                    ),
                  );
                  if (name == null || name.isEmpty || cats.any((c) => c.name == name)) return;
                  await _save(ref, [...cats, ExpenseCategory(name, emoji, _colors[cats.length % _colors.length])]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuánto llevas de cada presupuesto este mes.
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.budgets,
    required this.spent,
    required this.cats,
    required this.money,
    required this.month,
    required this.onEdit,
  });
  final Map<String, double> budgets;
  final Map<String, double> spent;
  final Map<String, ExpenseCategory> cats;
  final String Function(double) money;
  final String month;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Presupuesto de $month', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: onEdit),
              ],
            ),
            for (final e in budgets.entries)
              () {
                final s = spent[e.key] ?? 0;
                final f = s / e.value;
                final over = s > e.value;
                final cat = cats[e.key];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text('${cat?.emoji ?? '🛒'}  ${e.key}'),
                          const Spacer(),
                          Text('${money(s)} / ${money(e.value)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: over ? Colors.red.shade700 : null,
                              )),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: f.clamp(0, 1),
                          minHeight: 8,
                          backgroundColor: Colors.black.withValues(alpha: 0.06),
                          color: over
                              ? Colors.red.shade400
                              : f >= 0.8
                                  ? Colors.orange.shade400
                                  : const Color(0xFF7FB069),
                        ),
                      ),
                      if (over)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('Te pasaste ${money(s - e.value)}',
                              style: TextStyle(fontSize: 11.5, color: Colors.red.shade700)),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('Te quedan ${money(e.value - s)}',
                              style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
                        ),
                    ],
                  ),
                );
              }(),
          ],
        ),
      ),
    );
  }
}

/// Este mes contra el anterior, por categoría.
class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.rows,
    required this.total,
    required this.prevTotal,
    required this.cats,
    required this.money,
    required this.prevName,
  });
  final List<(String, double, double)> rows;
  final double total;
  final double prevTotal;
  final Map<String, ExpenseCategory> cats;
  final String Function(double) money;
  final String prevName;

  @override
  Widget build(BuildContext context) {
    final diff = total - prevTotal;
    final pct = prevTotal == 0 ? null : (diff * 100 / prevTotal).round();
    final maxV = rows.fold<double>(1, (m, r) => math.max(m, math.max(r.$2, r.$3)));
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Comparado con $prevName', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              prevTotal == 0
                  ? 'En $prevName no anotaste gastos.'
                  : diff.abs() < 0.5
                      ? 'Gastaste lo mismo que en $prevName.'
                      : diff > 0
                          ? '${money(diff)} más que en $prevName (+$pct %)'
                          : '${money(-diff)} menos que en $prevName ($pct %) 🎉',
              style: TextStyle(
                color: diff > 0 && prevTotal > 0 ? Colors.red.shade700 : const Color(0xFF4E7F3A),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _legend(const Color(0xFF7FB069), 'Este mes'),
                const SizedBox(width: 14),
                _legend(const Color(0xFFCFD8DC), prevName),
              ],
            ),
            const SizedBox(height: 6),
            for (final (name, now, before) in rows.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text('${cats[name]?.emoji ?? '🛒'} $name',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _bar(now / maxV, const Color(0xFF7FB069), money(now)),
                          const SizedBox(height: 2),
                          _bar(before / maxV, const Color(0xFFCFD8DC), money(before)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color c, String t) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
        ],
      );

  Widget _bar(double f, Color c, String label) => LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            Container(
              width: math.max(3, (box.maxWidth - 64) * f),
              height: 9,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
          ],
        ),
      );
}

/// Lista del súper: agregas lo que falta y al marcarlo como comprado se
/// anota el gasto.
class _ShoppingSheet extends ConsumerStatefulWidget {
  const _ShoppingSheet({required this.onBought});
  final Future<bool> Function(ShoppingItem item) onBought;

  @override
  ConsumerState<_ShoppingSheet> createState() => _ShoppingSheetState();
}

class _ShoppingSheetState extends ConsumerState<_ShoppingSheet> {
  final _name = TextEditingController();
  String? _cat;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _set(List<ShoppingItem> l) async {
    ref.read(shoppingProvider.notifier).state = l;
    await ref.read(sharedPreferencesProvider).setString('expenses.shopping', ShoppingItem.encodeAll(l));
  }

  void _add() {
    final t = _name.text.trim();
    if (t.isEmpty) return;
    final cats = ref.read(expenseCategoriesProvider);
    _set([
      ...ref.read(shoppingProvider),
      ShoppingItem(id: const Uuid().v4(), name: t, category: _cat ?? guessCategory(t, cats)),
    ]);
    _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(shoppingProvider);
    final cats = ref.watch(expenseCategoriesProvider);
    final byName = {for (final c in cats) c.name: c};
    final grouped = <String, List<ShoppingItem>>{};
    for (final i in items) {
      grouped.putIfAbsent(i.category, () => []).add(i);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lista del súper 🛒', style: fontStyle('Pacifico', size: 22)),
            const Text('Toca ☐ cuando lo compres y pon cuánto costó: se anota solo en Gastos.',
                style: TextStyle(color: Colors.black54, fontSize: 12.5)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Tomates, pollo, leche…'),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
              ],
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 6),
                    child: ChoiceChip(
                      label: const Text('Auto'),
                      selected: _cat == null,
                      onSelected: (_) => setState(() => _cat = null),
                    ),
                  ),
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.only(right: 6, top: 6),
                      child: ChoiceChip(
                        label: Text('${c.emoji} ${c.name}'),
                        selected: _cat == c.name,
                        onSelected: (_) => setState(() => _cat = c.name),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('La lista está vacía ✨', textAlign: TextAlign.center),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final g in grouped.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                      child: Text('${byName[g.key]?.emoji ?? '🛒'} ${g.key}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    for (final i in g.value)
                      Dismissible(
                        key: ValueKey(i.id),
                        onDismissed: (_) =>
                            _set([for (final x in ref.read(shoppingProvider)) if (x.id != i.id) x]),
                        child: CheckboxListTile(
                          value: false,
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          title: Text(i.name),
                          onChanged: (_) async {
                            if (await widget.onBought(i)) {
                              await _set([for (final x in ref.read(shoppingProvider)) if (x.id != i.id) x]);
                            }
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
