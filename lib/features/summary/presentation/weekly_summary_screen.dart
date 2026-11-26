import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/daily_stats.dart';
import '../../../core/providers.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/presentation/expenses_screen.dart';
import '../../journal/domain/journal.dart';
import '../../journal/presentation/journal_screen.dart';
import '../../notes/domain/note.dart';
import '../../planner/domain/planner.dart';
import '../../planner/presentation/planner_screen.dart';
import '../../settings/settings.dart';
import '../../study/domain/flashcard.dart';

const _days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// Gastos de la semana (de lunes a lunes).
final _weekExpensesProvider = StreamProvider.autoDispose.family<List<Expense>, DateTime>(
    (ref, from) => ref.watch(expensesRepositoryProvider).watchRange(from, from.add(const Duration(days: 7))));

/// Resumen de la semana: lo que hiciste y lo que viene.
class WeeklySummaryScreen extends ConsumerStatefulWidget {
  const WeeklySummaryScreen({super.key});

  @override
  ConsumerState<WeeklySummaryScreen> createState() => _WeeklySummaryScreenState();
}

class _WeeklySummaryScreenState extends ConsumerState<WeeklySummaryScreen> {
  int _back = 0; // 0 = esta semana, 1 = la pasada…

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final from = weekStart(now).subtract(Duration(days: 7 * _back));
    final to = from.add(const Duration(days: 7));
    final prefs = ref.watch(sharedPreferencesProvider);
    final notes = ref.watch(notesListProvider(null)).valueOrNull ?? const <Note>[];
    final cards = ref.watch(flashcardsProvider).valueOrNull ?? const <Flashcard>[];
    final expenses = ref.watch(_weekExpensesProvider(from)).valueOrNull ?? const <Expense>[];
    final journal = ref.watch(journalProvider);
    final planner = ref.watch(plannerProvider);
    final cur = ref.watch(currencyProvider);

    bool inWeek(DateTime d) => !d.isBefore(from) && d.isBefore(to);
    final newNotes = notes.where((n) => inWeek(n.createdAt)).toList();
    final edited = notes.where((n) => inWeek(n.updatedAt)).length;
    final pomodoros = DailyStats.sum(prefs, 'pomodoro', from, to);
    final reviews = DailyStats.sum(prefs, 'reviews', from, to);
    final dueCards = cards.where((c) => !c.due.isAfter(now)).length;
    final spent = expenses.fold<double>(0, (a, e) => a + e.amount);
    final byCat = <String, double>{};
    for (final e in expenses) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    final topCat = (byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).firstOrNull;
    final weekDays = [for (var i = 0; i < 7; i++) from.add(Duration(days: i))];
    final upcoming = planner.reminders
        .where((r) => !r.done && r.due.isAfter(now) && r.due.isBefore(now.add(const Duration(days: 8))))
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    final last = to.subtract(const Duration(days: 1));

    return Scaffold(
      appBar: AppBar(title: const Text('Resumen de la semana')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(children: [
            IconButton(
              tooltip: 'Semana anterior',
              onPressed: () => setState(() => _back++),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _back == 0
                    ? 'Esta semana · ${from.day}/${from.month} al ${last.day}/${last.month}'
                    : '${from.day}/${from.month} al ${last.day}/${last.month}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Semana siguiente',
              onPressed: _back > 0 ? () => setState(() => _back--) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _Stat('📝', '${newNotes.length}', 'notas nuevas', onTap: () => context.push('/notebooks/all')),
            _Stat('✏️', '$edited', 'notas editadas'),
            _Stat('🍅', '$pomodoros', 'pomodoros'),
            _Stat('🃏', '$reviews', 'tarjetas repasadas', onTap: () => context.push('/study')),
            _Stat('💸', '$cur ${spent.toStringAsFixed(spent % 1 == 0 ? 0 : 2)}', 'gastado',
                onTap: () => context.push('/expenses')),
          ]),
          if (dueCards > 0 && _back == 0)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: ListTile(
                leading: const Icon(Icons.style_outlined),
                title: Text('Tienes $dueCards tarjeta${dueCards == 1 ? '' : 's'} para repasar hoy'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/study'),
              ),
            ),
          if (topCat != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('En lo que más gastaste: ${topCat.key} ($cur ${topCat.value.toStringAsFixed(0)})'),
            ),
          const _Title('Ánimo'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (i, d) in weekDays.indexed)
                Column(children: [
                  Text(journal.day(d).mood?.emoji ?? '·', style: const TextStyle(fontSize: 26)),
                  Text(_days[i], style: const TextStyle(fontSize: 12)),
                ]),
            ],
          ),
          if (journal.habits.isNotEmpty) ...[
            const _Title('Hábitos'),
            for (final h in journal.habits)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 110, child: Text('${h.emoji} ${h.name}', overflow: TextOverflow.ellipsis)),
                  for (final d in weekDays)
                    Expanded(
                      child: Icon(
                        journal.isDone(h.id, d) ? Icons.check_circle : Icons.circle_outlined,
                        size: 20,
                        color: journal.isDone(h.id, d) ? Colors.green : Colors.black26,
                      ),
                    ),
                  SizedBox(
                    width: 32,
                    child: Text('${weekDays.where((d) => journal.isDone(h.id, d)).length}/7',
                        textAlign: TextAlign.end, style: const TextStyle(fontSize: 12)),
                  ),
                ]),
              ),
          ],
          const _Title('Lo que viene'),
          if (upcoming.isEmpty)
            const Text('Nada pendiente en los próximos días 🎉')
          else
            for (final r in upcoming)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(r.kind.emoji, style: const TextStyle(fontSize: 24)),
                title: Text(r.title),
                subtitle: Text([if (r.subject.isNotEmpty) r.subject, dueLabel(r.due, now)].join(' · ')),
                onTap: () => context.push('/planner?tab=pendientes'),
              ),
          if (newNotes.isNotEmpty) ...[
            const _Title('Notas nuevas'),
            for (final n in newNotes.take(8))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(n.displayTitle),
                subtitle: Text('${_days[n.createdAt.weekday - 1]} ${n.createdAt.day}/${n.createdAt.month}'),
                onTap: () => context.push('/notes/${n.id}'),
              ),
          ],
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.emoji, this.value, this.label, {this.onTap});
  final String emoji;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.sizeOf(context).width - 32 - 10) / 2;
    return SizedBox(
      width: w,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(label, style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
