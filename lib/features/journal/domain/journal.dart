import 'dart:convert';

/// Ánimos del calendario, de mejor a peor.
enum Mood {
  great('😄', 'Genial', 0xFFFFD166),
  good('🙂', 'Bien', 0xFFA8D5A2),
  meh('😐', 'Normal', 0xFFCFD8DC),
  sad('😢', 'Triste', 0xFF9CC5E8),
  angry('😠', 'Enojada', 0xFFF4A3A3),
  tired('😴', 'Cansada', 0xFFC9B3E8);

  const Mood(this.emoji, this.label, this.color);
  final String emoji;
  final String label;
  final int color;
}

/// Lo anotado en un día: ánimo y una línea de diario.
class DayEntry {
  const DayEntry({this.mood, this.text = ''});
  final Mood? mood;
  final String text;

  bool get isEmpty => mood == null && text.trim().isEmpty;

  Map<String, Object?> toJson() => {if (mood != null) 'mood': mood!.name, if (text.isNotEmpty) 'text': text};

  factory DayEntry.fromJson(Map<String, Object?> j) => DayEntry(
        mood: Mood.values.where((m) => m.name == j['mood']).firstOrNull,
        text: j['text'] as String? ?? '',
      );
}

class Habit {
  const Habit({required this.id, required this.name, this.emoji = '⭐'});
  final String id;
  final String name;
  final String emoji;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'emoji': emoji};
  factory Habit.fromJson(Map<String, Object?> j) =>
      Habit(id: j['id'] as String, name: j['name'] as String, emoji: j['emoji'] as String? ?? '⭐');
}

/// Clave de un día: "2026-11-25".
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Lunes de la semana de [d].
DateTime weekStart(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

class JournalState {
  const JournalState({this.days = const {}, this.habits = const [], this.done = const {}});

  final Map<String, DayEntry> days;
  final List<Habit> habits;

  /// Hábito → días cumplidos.
  final Map<String, Set<String>> done;

  DayEntry day(DateTime d) => days[dayKey(d)] ?? const DayEntry();

  bool isDone(String habitId, DateTime d) => done[habitId]?.contains(dayKey(d)) ?? false;

  /// Días seguidos cumplidos hasta hoy (si hoy aún no, cuenta desde ayer).
  int streak(String habitId, DateTime today) {
    var d = DateTime(today.year, today.month, today.day);
    if (!isDone(habitId, d)) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (isDone(habitId, d)) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  /// Cuántos días del mes tuvieron cada ánimo.
  Map<Mood, int> moodCounts(int year, int month) {
    final out = <Mood, int>{};
    final prefix = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-';
    days.forEach((k, v) {
      if (k.startsWith(prefix) && v.mood != null) out[v.mood!] = (out[v.mood!] ?? 0) + 1;
    });
    return out;
  }

  JournalState copyWith({
    Map<String, DayEntry>? days,
    List<Habit>? habits,
    Map<String, Set<String>>? done,
  }) =>
      JournalState(days: days ?? this.days, habits: habits ?? this.habits, done: done ?? this.done);

  JournalState setDay(DateTime d, DayEntry e) {
    final next = {...days};
    if (e.isEmpty) {
      next.remove(dayKey(d));
    } else {
      next[dayKey(d)] = e;
    }
    return copyWith(days: next);
  }

  JournalState toggle(String habitId, DateTime d) {
    final set = {...?done[habitId]};
    final k = dayKey(d);
    if (!set.remove(k)) set.add(k);
    return copyWith(done: {...done, habitId: set});
  }

  String encode() => jsonEncode({
        'days': {for (final e in days.entries) e.key: e.value.toJson()},
        'habits': [for (final h in habits) h.toJson()],
        'done': {for (final e in done.entries) e.key: e.value.toList()..sort()},
      });

  factory JournalState.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const JournalState();
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      return JournalState(
        days: {
          for (final e in (j['days'] as Map? ?? const {}).entries)
            e.key as String: DayEntry.fromJson((e.value as Map).cast<String, Object?>()),
        },
        habits: [
          for (final h in (j['habits'] as List? ?? const []))
            Habit.fromJson((h as Map).cast<String, Object?>()),
        ],
        done: {
          for (final e in (j['done'] as Map? ?? const {}).entries)
            e.key as String: {for (final d in e.value as List) d as String},
        },
      );
    } catch (_) {
      return const JournalState();
    }
  }
}
