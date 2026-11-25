import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../journal/domain/journal.dart';
import '../../journal/presentation/journal_screen.dart';
import '../../planner/domain/planner.dart';
import '../../planner/presentation/planner_screen.dart';
import '../../settings/settings.dart';

/// Lo que dicen los gatitos al abrir la app: saludo con tu nombre según la
/// hora, o un aviso si hay examen, clase o hábitos.
String catGreeting(WidgetRef ref, {DateTime? now}) {
  final t = now ?? DateTime.now();
  final name = ref.read(sharedPreferencesProvider).getString('user.name')?.trim() ?? '';
  final you = name.isEmpty ? '' : ', $name';
  final planner = ref.read(plannerProvider);
  final journal = ref.read(journalProvider);
  return greetingFor(t, you: you, planner: planner, journal: journal);
}

String greetingFor(DateTime t, {String you = '', PlannerState? planner, JournalState? journal}) {
  // 1) Examen o entrega en menos de 2 días.
  final soon = planner?.upcoming
      .where((r) => r.due.isAfter(t) && r.due.difference(t) < const Duration(days: 2))
      .firstOrNull;
  if (soon != null) return '${soon.kind.emoji} ${soon.title} ${dueLabel(soon.due, t)}. ¡Tú puedes$you!';
  // 2) Clase en la próxima hora.
  final next = planner?.currentOrNext(t);
  final m = t.hour * 60 + t.minute;
  if (next != null && next.start - m <= 60) {
    return next.start <= m
        ? 'Estás en ${next.subject}. ¿Grabamos la clase? 🎙️'
        : 'A las ${hhmm(next.start)} tienes ${next.subject} 📚';
  }
  // 3) Todos los hábitos de hoy hechos.
  final habits = journal?.habits ?? const <Habit>[];
  if (habits.isNotEmpty && habits.every((h) => journal!.isDone(h.id, t))) {
    return '¡Hiciste todos tus hábitos hoy$you! 🎉';
  }
  // 4) Saludo según la hora (de noche, los gatitos duermen).
  if (t.hour >= 23 || t.hour < 5) return 'Zzz… ya es tarde$you, a dormir 😴';
  if (t.hour < 12) return '¡Buenos días$you! ☀️';
  if (t.hour < 19) return '¡Buenas tardes$you! 🌤️';
  return '¡Buenas noches$you! 🌙';
}
