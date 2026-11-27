import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/cat_mascot.dart';
import '../../settings/settings.dart';
import '../domain/journal.dart';
import 'journal_art.dart';

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

/// Con la ventana así de ancha (compu) se usa el diseño de dos columnas.
const _wideAt = 900.0;

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
    final counts = st.moodCounts(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final notes = [
      for (var d = daysInMonth; d >= 1; d--)
        if (st.day(DateTime(_month.year, _month.month, d)) case final e when e.text.isNotEmpty)
          (DateTime(_month.year, _month.month, d), e),
    ];

    final calendar = [
      _monthHeader(context),
      const SizedBox(height: 4),
      Row(
        children: [
          for (final l in _weekLetters)
            Expanded(
              child: Center(
                child: Text(l, style: const TextStyle(color: Color(0xFF7A8C99), fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      _MonthGrid(month: _month, state: st, onTap: (d) => editDay(context, ref, d)),
    ];
    final side = [
      _MonthSummary(counts: counts),
      for (final (d, e) in notes) _NoteCard(date: d, entry: e, onTap: () => editDay(context, ref, d)),
    ];

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= _wideAt;
      final sceneH = wide ? 250.0 : 210.0;
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [skyTop, skyBottom],
          ),
        ),
        child: Stack(
          children: [
            if (wide) ...[
              Positioned(left: 0, right: 0, bottom: 0, height: sceneH, child: const MeadowScene()),
              Positioned(
                right: c.maxWidth * 0.12,
                bottom: sceneH * 0.1,
                child: const AnimatedCatMascot(kind: CatKind.gray, size: 92),
              ),
            ],
            if (wide)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(32, 16, 24, sceneH * 0.7),
                          children: calendar,
                        ),
                      ),
                      SizedBox(
                        width: 360,
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(0, 76, 32, sceneH * 0.7),
                          children: side,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    sliver: SliverList.list(children: [...calendar, const SizedBox(height: 12), ...side]),
                  ),
                  // La pradera va al final: abajo de todo si sobra espacio.
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        height: sceneH,
                        child: Stack(
                          children: [
                            const Positioned.fill(child: MeadowScene()),
                            Positioned(
                              right: 24,
                              bottom: sceneH * 0.1,
                              child: const AnimatedCatMascot(kind: CatKind.gray, size: 70),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    });
  }

  Widget _monthHeader(BuildContext context) => Row(
        children: [
          IconButton(
            tooltip: 'Mes anterior',
            icon: const Icon(Icons.chevron_left_rounded, size: 30),
            onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
          ),
          Expanded(
            child: Text(
              '${_monthNames[_month.month - 1]} ${_month.year}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF4F6575),
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          IconButton(
            tooltip: 'Mes siguiente',
            icon: const Icon(Icons.chevron_right_rounded, size: 30),
            onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
          ),
        ],
      );
}

/// Cuadrícula del mes: una nubecita por día y su número abajo.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.state, required this.onTap});
  final DateTime month;
  final JournalState state;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayKey = dayKey(today);
    final lead = DateTime(month.year, month.month).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return LayoutBuilder(builder: (context, c) {
      final face = math.min(c.maxWidth / 7 * 0.9, 68.0);
      return Column(
        children: [
          for (var r = 0; r < cells.length; r += 7)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (final d in cells.sublist(r, r + 7))
                    Expanded(
                      child: d == null
                          ? const SizedBox()
                          : _DayCell(
                              date: d,
                              entry: state.day(d),
                              size: face,
                              isToday: dayKey(d) == todayKey,
                              isFuture: d.isAfter(today),
                              onTap: () => onTap(d),
                            ),
                    ),
                ],
              ),
            ),
        ],
      );
    });
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.entry,
    required this.size,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });
  final DateTime date;
  final DayEntry entry;
  final double size;
  final bool isToday;
  final bool isFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final number = Text(
      '${date.day}',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isToday ? Colors.white : const Color(0xFF6F7F8A),
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(size),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MoodFace(mood: entry.mood, size: size, faded: isFuture),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              isToday
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5AAE6B),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: number,
                    )
                  : number,
              if (entry.text.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 1),
                  child: Icon(Icons.edit_note_rounded, size: 14, color: Color(0xFF6F7F8A)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tarjeta "así va tu mes" con cuántos días de cada ánimo.
class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.counts});
  final Map<Mood, int> counts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(22),
      ),
      child: counts.isEmpty
          ? const Row(
              children: [
                CatMascot(kind: CatKind.orange, size: 44),
                SizedBox(width: 12),
                Expanded(child: Text('Toca un día para anotar cómo te sentiste.')),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Así va tu mes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    for (final m in Mood.values)
                      if (counts[m] case final n?)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MoodFace(mood: m, size: 30),
                            const SizedBox(width: 4),
                            Text('${m.label} · $n'),
                          ],
                        ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.date, required this.entry, required this.onTap});
  final DateTime date;
  final DayEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                entry.mood == null
                    ? CircleAvatar(backgroundColor: const Color(0xFFEFF5F9), child: Text('${date.day}'))
                    : MoodFace(mood: entry.mood, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text('${date.day} de ${_monthNames[date.month - 1].toLowerCase()}',
                          style: const TextStyle(fontSize: 12, color: Colors.black45)),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
    backgroundColor: const Color(0xFFF4FAFD),
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
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in Mood.values)
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => setSheet(() => mood = mood == m ? null : m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 76,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: mood == m ? moodColors(m).$1.withValues(alpha: 0.45) : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: mood == m ? moodColors(m).$2 : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          AnimatedScale(
                            scale: mood == m ? 1.12 : 1,
                            duration: const Duration(milliseconds: 160),
                            child: MoodFace(mood: m, size: 50),
                          ),
                          Text(m.label, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
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

/// Patitas que se ganan por cada hábito cumplido.
const habitPoints = 5;

const _meadow = Color(0xFFA6D08A);
const _meadowDark = Color(0xFF8DBF70);
const _leafInk = Color(0xFF2F5A2A);

class HabitTracker extends ConsumerStatefulWidget {
  const HabitTracker({super.key, this.initialWeek});
  final DateTime? initialWeek;

  @override
  ConsumerState<HabitTracker> createState() => _HabitTrackerState();
}

class _HabitTrackerState extends ConsumerState<HabitTracker> {
  /// Día que se está marcando (hoy, salvo que se elija otro en la semana).
  late DateTime _day = () {
    final now = DateTime.now();
    final w = widget.initialWeek;
    if (w == null || weekStart(w) == weekStart(now)) return DateTime(now.year, now.month, now.day);
    return weekStart(w);
  }();

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(journalProvider);
    final done = st.habits.where((h) => st.isDone(h.id, _day)).length;
    final total = st.habits.length;
    final progress = total == 0 ? 0.0 : done / total;
    final points = st.done.values.fold<int>(0, (a, s) => a + s.length) * habitPoints;

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= _wideAt;
      final list = <Widget>[
        _header(context, total - done),
        _weekStrip(),
        const SizedBox(height: 6),
        if (st.habits.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: const Column(
              children: [
                CatMascot(kind: CatKind.gray, size: 80),
                SizedBox(height: 10),
                Text('Agrega hábitos como "Tomar agua 💧" o "Leer 📚"\ny márcalos cada día con ✓.',
                    textAlign: TextAlign.center),
              ],
            ),
          )
        else
          for (final (i, h) in st.habits.indexed)
            _HabitCard(
              habit: h,
              color: habitColors[i % habitColors.length],
              streak: st.streak(h.id, DateTime.now()),
              done: st.isDone(h.id, _day),
              enabled: !_day.isAfter(DateTime.now()),
              onEdit: () => _editHabit(context, h),
              onToggle: () => _toggle(context, h),
            ),
      ];
      final progressCard = _ProgressCard(done: done, total: total, points: points, isToday: _isToday);
      final fab = FloatingActionButton.extended(
        elevation: 2,
        shape: const StadiumBorder(side: BorderSide(color: _meadowDark, width: 2)),
        backgroundColor: Colors.white,
        foregroundColor: _leafInk,
        onPressed: () => _editHabit(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Hábito'),
      );

      if (wide) {
        return Scaffold(
          backgroundColor: _meadow,
          floatingActionButton: fab,
          body: Row(
            children: [
              SizedBox(
                width: math.min(c.maxWidth * 0.42, 560),
                child: _Garden(progress: progress),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 100),
                      children: [progressCard, const SizedBox(height: 8), ...list],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return Scaffold(
        backgroundColor: _meadow,
        floatingActionButton: fab,
        body: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            SizedBox(height: 250, child: _Garden(progress: progress)),
            Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 0), child: progressCard),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Column(children: list)),
          ],
        ),
      );
    });
  }

  bool get _isToday => dayKey(_day) == dayKey(DateTime.now());

  void _toggle(BuildContext context, Habit h) {
    ref.read(journalProvider.notifier).toggle(h.id, _day);
    final after = ref.read(journalProvider);
    if (_isToday && after.isDone(h.id, _day) && after.habits.every((x) => after.isDone(x.id, _day))) {
      _celebrate(context);
    }
  }

  Widget _header(BuildContext context, int left) {
    final when = _isToday ? 'para hoy' : 'el ${_day.day} de ${_monthNames[_day.month - 1].toLowerCase()}';
    final text = left == 0
        ? (_isToday ? '¡Todo listo por hoy! 🎉' : 'Todo hecho $when')
        : left == 1
            ? '¡Te queda 1 hábito $when!'
            : '¡Te quedan $left hábitos $when!';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded, color: _leafInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: _leafInk, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Los 7 días de la semana: se toca uno para marcar sus hábitos.
  Widget _weekStrip() {
    final start = weekStart(_day);
    final today = DateTime.now();
    return Row(
      children: [
        IconButton(
          tooltip: 'Semana anterior',
          visualDensity: VisualDensity.compact,
          color: _leafInk,
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => setState(() => _day = DateTime(_day.year, _day.month, _day.day - 7)),
        ),
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(builder: (context) {
              final d = DateTime(start.year, start.month, start.day + i);
              final selected = dayKey(d) == dayKey(_day);
              final isToday = dayKey(d) == dayKey(today);
              return GestureDetector(
                onTap: () => setState(() => _day = d),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(_weekLetters[i],
                          style: TextStyle(fontSize: 11, color: _leafInk.withValues(alpha: 0.7))),
                      Text(
                        '${d.day}',
                        style: TextStyle(
                          fontWeight: isToday || selected ? FontWeight.bold : FontWeight.normal,
                          color: isToday ? const Color(0xFFE07B55) : _leafInk,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        IconButton(
          tooltip: 'Semana siguiente',
          visualDensity: VisualDensity.compact,
          color: _leafInk,
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => setState(() => _day = DateTime(_day.year, _day.month, _day.day + 7)),
        ),
      ],
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

/// El jardín con el gatito parado en el caminito.
class _Garden extends StatelessWidget {
  const _Garden({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final box = gardenBoxHeight(c.biggest);
        final cat = box * 0.27;
        return Stack(
          children: [
            Positioned.fill(child: ClipRect(child: GardenScene(progress: progress))),
            Positioned(
              left: c.maxWidth * 0.58 - cat / 2,
              top: c.maxHeight - box * 0.1 - cat * 1.1,
              child: AnimatedCatMascot(size: cat),
            ),
          ],
        );
      });
}

/// Tarjeta de avance del día: corazón → nubecita → estrella.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.done, required this.total, required this.points, required this.isToday});
  final int done;
  final int total;
  final int points;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final f = total == 0 ? 0.0 : done / total;
    const white = TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(color: _meadowDark, borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(isToday ? 'Tu día · $done de $total' : '$done de $total', style: white)),
              const Icon(Icons.pets, color: Colors.white, size: 18),
              const SizedBox(width: 4),
              Text('$points patitas', style: white),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: LayoutBuilder(builder: (context, c) {
              const r = 18.0;
              final span = c.maxWidth - 2 * r;
              final x = r + span * f;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Caminito de puntitos.
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: r),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < (span / 14).floor(); i++)
                            Container(
                              width: 8,
                              height: 5,
                              decoration: BoxDecoration(
                                color: _leafInk.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Lo avanzado.
                  Positioned(
                    left: r,
                    top: 16,
                    width: math.max(0, x - r),
                    height: 8,
                    child: DecoratedBox(
                      decoration:
                          BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const Positioned(left: 0, top: 2, child: _TrailStop(icon: Icons.favorite_rounded)),
                  const Positioned(right: 0, top: 2, child: _TrailStop(icon: Icons.star_rounded)),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    left: x - 22,
                    top: -4,
                    child: MoodFace(mood: f >= 1 ? Mood.great : Mood.good, size: 44),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _TrailStop extends StatelessWidget {
  const _TrailStop({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF3E4A5A),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      );
}

/// Tarjeta blanca y redondita de un hábito, con su botón ✓.
class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.habit,
    required this.color,
    required this.streak,
    required this.done,
    required this.enabled,
    required this.onEdit,
    required this.onToggle,
  });
  final Habit habit;
  final Color color;
  final int streak;
  final bool done;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                HabitBadge(emoji: habit.emoji, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: Colors.black38,
                        ),
                      ),
                      Text(
                        streak == 0 ? 'Empieza tu racha hoy' : '🔥 $streak ${streak == 1 ? 'día' : 'días'} seguidos',
                        style: t.bodySmall?.copyWith(color: Colors.black45),
                      ),
                    ],
                  ),
                ),
                Text('$habitPoints', style: t.titleMedium?.copyWith(color: Colors.black54)),
                const SizedBox(width: 2),
                const Icon(Icons.pets, size: 16, color: Color(0xFF3E4A5A)),
                const SizedBox(width: 10),
                _CheckButton(done: done, enabled: enabled, onTap: onToggle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckButton extends StatelessWidget {
  const _CheckButton({required this.done, required this.enabled, required this.onTap});
  final bool done;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF6BBF5E);
    return Semantics(
      button: true,
      checked: done,
      label: done ? 'Hecho' : 'Marcar como hecho',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 56,
            height: 50,
            decoration: BoxDecoration(
              color: done ? green : const Color(0xFFF3F1ED),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: done ? const Color(0xFF4E9A44) : const Color(0xFFD9D5CE),
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(Icons.check_rounded, size: 32, color: done ? Colors.white : green),
          ),
        ),
      ),
    );
  }
}
