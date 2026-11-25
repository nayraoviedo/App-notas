import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/cat_mascot.dart';
import '../../settings/settings.dart';
import '../domain/journal.dart';

class JournalController extends Notifier<JournalState> {
  static const _key = 'journal.data';

  @override
  JournalState build() => JournalState.decode(ref.watch(sharedPreferencesProvider).getString(_key));

  void _save(JournalState s) {
    state = s;
    ref.read(sharedPreferencesProvider).setString(_key, s.encode());
  }

  void setDay(DateTime d, DayEntry e) => _save(state.setDay(d, e));
  void toggle(String habitId, DateTime d) => _save(state.toggle(habitId, d));

  void addHabit(String name, String emoji) => _save(state.copyWith(
        habits: [...state.habits, Habit(id: const Uuid().v4(), name: name, emoji: emoji)],
      ));

  void renameHabit(Habit h, String name, String emoji) => _save(state.copyWith(habits: [
        for (final x in state.habits) x.id == h.id ? Habit(id: h.id, name: name, emoji: emoji) : x,
      ]));

  void deleteHabit(Habit h) => _save(state.copyWith(
        habits: [for (final x in state.habits) if (x.id != h.id) x],
        done: {...state.done}..remove(h.id),
      ));
}

final journalProvider = NotifierProvider<JournalController, JournalState>(JournalController.new);

const _monthNames = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];
const _weekLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// Diario: calendario de ánimos (con una línea por día) y hábitos.
class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Color(0xFFFFF9EE),
        appBar: _JournalBar(),
        body: TabBarView(children: [MoodCalendar(), HabitTracker()]),
      ),
    );
  }
}

class _JournalBar extends StatelessWidget implements PreferredSizeWidget {
  const _JournalBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 48);

  @override
  Widget build(BuildContext context) => AppBar(
        backgroundColor: const Color(0xFFFCF0DF),
        title: const Text('Mi diario'),
        bottom: const TabBar(tabs: [Tab(text: 'Ánimo'), Tab(text: 'Hábitos')]),
      );
}

// ------------------------------------------------------------------ Ánimos

class MoodCalendar extends ConsumerStatefulWidget {
  const MoodCalendar({super.key, this.initialMonth});
  final DateTime? initialMonth;

  @override
  ConsumerState<MoodCalendar> createState() => _MoodCalendarState();
}

class _MoodCalendarState extends ConsumerState<MoodCalendar> {
  late DateTime _month = () {
    final d = widget.initialMonth ?? DateTime.now();
    return DateTime(d.year, d.month);
  }();

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(journalProvider);
    final today = DateTime.now();
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final counts = st.moodCounts(_month.year, _month.month);
    final notes = [
      for (var d = daysInMonth; d >= 1; d--)
        if (st.day(DateTime(_month.year, _month.month, d)) case final e when e.text.isNotEmpty)
          (DateTime(_month.year, _month.month, d), e),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
            ),
            Expanded(
              child: Text('${_monthNames[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
          ],
        ),
        Row(
          children: [
            for (final l in _weekLetters)
              Expanded(
                child: Center(
                  child: Text(l, style: const TextStyle(color: Colors.black45, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox(),
            for (var d = 1; d <= daysInMonth; d++)
              _DayCell(
                date: DateTime(_month.year, _month.month, d),
                entry: st.day(DateTime(_month.year, _month.month, d)),
                isToday: today.year == _month.year && today.month == _month.month && today.day == d,
                onTap: () => editDay(context, ref, DateTime(_month.year, _month.month, d)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: counts.isEmpty
                ? const Row(
                    children: [
                      CatMascot(kind: CatKind.orange, size: 44),
                      SizedBox(width: 12),
                      Expanded(child: Text('Toca un día para anotar cómo te sentiste.')),
                    ],
                  )
                : Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: [
                      for (final m in Mood.values)
                        if (counts[m] case final n?)
                          Chip(
                            backgroundColor: Color(m.color),
                            label: Text('${m.emoji} ${m.label} · $n'),
                          ),
                    ],
                  ),
          ),
        ),
        for (final (d, e) in notes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: e.mood == null ? Colors.black12 : Color(e.mood!.color),
              child: Text(e.mood?.emoji ?? '${d.day}'),
            ),
            title: Text(e.text, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${d.day} de ${_monthNames[d.month - 1].toLowerCase()}'),
            onTap: () => editDay(context, ref, d),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.date, required this.entry, required this.isToday, required this.onTap});
  final DateTime date;
  final DayEntry entry;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mood = entry.mood;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: mood == null ? Colors.white : Color(mood.color),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isToday ? const Color(0xFFE07B55) : Colors.black12,
            width: isToday ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 4,
              top: 2,
              child: Text('${date.day}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
            ),
            if (mood != null) Center(child: Text(mood.emoji, style: const TextStyle(fontSize: 20))),
            if (entry.text.isNotEmpty)
              const Positioned(right: 4, bottom: 3, child: Icon(Icons.edit_note, size: 12, color: Colors.black45)),
          ],
        ),
      ),
    );
  }
}

/// Elegir el ánimo y escribir una línea del día.
Future<void> editDay(BuildContext context, WidgetRef ref, DateTime d) async {
  final current = ref.read(journalProvider).day(d);
  var mood = current.mood;
  final text = TextEditingController(text: current.text);
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${d.day} de ${_monthNames[d.month - 1].toLowerCase()}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('¿Cómo te sentiste?'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in Mood.values)
                  ChoiceChip(
                    selected: mood == m,
                    selectedColor: Color(m.color),
                    label: Text('${m.emoji} ${m.label}'),
                    onSelected: (v) => setSheet(() => mood = v ? m : null),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: text,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: '¿Qué pasó hoy? Algo bonito, algo que aprendiste…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
          ],
        ),
      ),
    ),
  );
  if (ok == true) {
    ref.read(journalProvider.notifier).setDay(d, DayEntry(mood: mood, text: text.text.trim()));
  }
}

// ----------------------------------------------------------------- Hábitos

class HabitTracker extends ConsumerStatefulWidget {
  const HabitTracker({super.key, this.initialWeek});
  final DateTime? initialWeek;

  @override
  ConsumerState<HabitTracker> createState() => _HabitTrackerState();
}

class _HabitTrackerState extends ConsumerState<HabitTracker> {
  late DateTime _week = weekStart(widget.initialWeek ?? DateTime.now());

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(journalProvider);
    final today = DateTime.now();
    final days = [for (var i = 0; i < 7; i++) DateTime(_week.year, _week.month, _week.day + i)];
    final end = days.last;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editHabit(context),
        icon: const Icon(Icons.add),
        label: const Text('Hábito'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _week = DateTime(_week.year, _week.month, _week.day - 7)),
              ),
              Expanded(
                child: Text(
                  '${_week.day} ${_monthNames[_week.month - 1].substring(0, 3).toLowerCase()} – '
                  '${end.day} ${_monthNames[end.month - 1].substring(0, 3).toLowerCase()}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _week = DateTime(_week.year, _week.month, _week.day + 7)),
              ),
            ],
          ),
          if (st.habits.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  CatMascot(kind: CatKind.gray, size: 90),
                  SizedBox(height: 12),
                  Text('Agrega hábitos como "Tomar agua 💧" o "Leer 📚"\ny márcalos tocando cada día.',
                      textAlign: TextAlign.center),
                ],
              ),
            )
          else ...[
            Row(
              children: [
                const SizedBox(width: 118),
                for (final (i, d) in days.indexed)
                  Expanded(
                    child: Column(
                      children: [
                        Text(_weekLetters[i], style: const TextStyle(fontSize: 11, color: Colors.black45)),
                        Text('${d.day}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: dayKey(d) == dayKey(today) ? FontWeight.bold : FontWeight.normal,
                              color: dayKey(d) == dayKey(today) ? const Color(0xFFE07B55) : Colors.black87,
                            )),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (final h in st.habits)
              Card(
                color: Colors.white,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 112,
                        child: InkWell(
                          onLongPress: () => _editHabit(context, h),
                          onTap: () => _editHabit(context, h),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${h.emoji} ${h.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
                              Text('🔥 ${st.streak(h.id, today)} días',
                                  style: const TextStyle(fontSize: 11, color: Colors.black45)),
                            ],
                          ),
                        ),
                      ),
                      for (final d in days)
                        Expanded(
                          child: Center(
                            child: _HabitDot(
                              done: st.isDone(h.id, d),
                              future: d.isAfter(today),
                              onTap: () {
                                ref.read(journalProvider.notifier).toggle(h.id, d);
                                final after = ref.read(journalProvider);
                                if (dayKey(d) == dayKey(today) &&
                                    after.isDone(h.id, d) &&
                                    after.habits.every((x) => after.isDone(x.id, d))) {
                                  _celebrate(context);
                                }
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Todos los hábitos de hoy hechos: ¡los gatitos celebran!
  void _celebrate(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/stickers/cat_05.png', width: 150, height: 150),
            const SizedBox(height: 8),
            Text('¡Todos tus hábitos de hoy! 🎉',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const Text('Los gatitos están orgullosos de ti.', textAlign: TextAlign.center),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('¡Miau!'))],
      ),
    );
  }

  Future<void> _editHabit(BuildContext context, [Habit? h]) async {
    final name = TextEditingController(text: h?.name ?? '');
    var emoji = h?.emoji ?? '⭐';
    const emojis = ['⭐', '💧', '📚', '🏃‍♀️', '🧘‍♀️', '😴', '🥗', '💊', '✍️', '🐱', '🧹', '💰', '🎨', '🎵'];
    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(h == null ? 'Nuevo hábito' : 'Editar hábito'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Tomar agua'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                children: [
                  for (final e in emojis)
                    ChoiceChip(
                      label: Text(e),
                      selected: e == emoji,
                      onSelected: (_) => setD(() => emoji = e),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            if (h != null)
              TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('Borrar')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    final ctl = ref.read(journalProvider.notifier);
    if (action == 'delete' && h != null) ctl.deleteHabit(h);
    if (action == 'save' && name.text.trim().isNotEmpty) {
      h == null ? ctl.addHabit(name.text.trim(), emoji) : ctl.renameHabit(h, name.text.trim(), emoji);
    }
  }
}

class _HabitDot extends StatelessWidget {
  const _HabitDot({required this.done, required this.future, required this.onTap});
  final bool done;
  final bool future;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: future ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? const Color(0xFFA8D5A2) : Colors.transparent,
          border: Border.all(color: future ? Colors.black12 : const Color(0xFF7CA65A), width: 1.6),
        ),
        child: done ? const Icon(Icons.pets, size: 16, color: Color(0xFF3B2A22)) : null,
      ),
    );
  }
}
