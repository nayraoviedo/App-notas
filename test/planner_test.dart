import 'dart:typed_data';

import 'package:app_notas/features/camera/background_remover.dart';
import 'package:app_notas/features/notebooks/presentation/cat_greeting.dart';
import 'package:app_notas/features/planner/domain/planner.dart';
import 'package:app_notas/features/study/domain/flashcard.dart';
import 'package:app_notas/features/study/presentation/exam_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;

void main() {
  final now = DateTime(2026, 11, 25, 9, 30); // miércoles

  test('horario y pendientes se guardan y se leen', () {
    final st = PlannerState(
      classes: const [
        ClassSlot(id: 'a', subject: 'Biología', weekday: 3, start: 10 * 60, end: 12 * 60, room: 'A-12'),
        ClassSlot(id: 'b', subject: 'Química', weekday: 3, start: 8 * 60, end: 9 * 60 + 30),
      ],
      reminders: [
        Reminder(id: 'r', title: 'Parcial', due: DateTime(2026, 11, 26, 8), subject: 'Biología'),
      ],
    );
    final back = PlannerState.decode(st.encode());
    expect(back.classesOn(3).map((c) => c.subject), ['Química', 'Biología']);
    expect(back.currentOrNext(now)!.subject, 'Biología'); // Química ya terminó a las 9:30
    expect(back.upcoming.single.title, 'Parcial');
    expect(back.subjects, ['Biología', 'Química']);
    expect(back.reminders.single.notifyBefore, [const Duration(days: 1), const Duration(hours: 2)]);
  });

  test('avisos solo a futuro y etiqueta de fecha', () {
    final r = Reminder(id: 'x', title: 'Entrega', due: DateTime(2026, 11, 26, 8));
    expect(r.alertTimes(now), [DateTime(2026, 11, 26, 6)]); // el de 1 día antes ya pasó
    expect(dueLabel(DateTime(2026, 11, 26, 8), now), 'mañana 08:00');
    expect(dueLabel(DateTime(2026, 11, 25, 14, 5), now), 'hoy 14:05');
    expect(dueLabel(DateTime(2026, 12, 9), now), 'en 2 semanas');
    expect(dueLabel(DateTime(2026, 11, 22), now), 'hace 3 días');
  });

  test('los gatitos avisan del examen, de la clase o saludan', () {
    final st = PlannerState(
      classes: const [ClassSlot(id: 'a', subject: 'Biología', weekday: 3, start: 10 * 60, end: 12 * 60)],
    );
    expect(greetingFor(now, you: ', Nayra', planner: st), 'A las 10:00 tienes Biología 📚');
    final withExam = st.copyWith(reminders: [
      Reminder(id: 'r', title: 'Parcial', due: DateTime(2026, 11, 26, 8)),
    ]);
    expect(greetingFor(now, planner: withExam), startsWith('📝 Parcial mañana 08:00'));
    expect(greetingFor(DateTime(2026, 11, 25, 8), you: ', Nayra'), '¡Buenos días, Nayra! ☀️');
    expect(greetingFor(DateTime(2026, 11, 25, 23, 40)), contains('Zzz'));
  });

  test('modo examen: 4 opciones y una correcta', () {
    final cards = [
      for (var i = 0; i < 6; i++)
        Flashcard(id: '$i', front: 'P$i', back: 'R$i', due: DateTime(2026, 11, 20 + i)),
    ];
    final exam = buildExam(cards, count: 5, random: math.Random(1));
    expect(exam.length, 5);
    for (final q in exam) {
      expect(q.options.length, 4);
      expect(q.options[q.correct], q.card.back);
      expect(q.options.toSet().length, 4);
    }
    expect(buildExam(cards.take(1).toList()), isEmpty);
  });

  test('quitar fondo: la máscara pasa al canal alfa (también si viene de otro tamaño)', () {
    final px = Uint8List.fromList(List.filled(4 * 4 * 4, 255));
    final out = applyMask((px, [1.0, 0.0, 0.0, 1.0], 4, 4)); // máscara 2x2
    expect(out[3], 255); // arriba izquierda: se queda
    expect(out[(0 * 4 + 3) * 4 + 3], 0); // arriba derecha: se va
    expect(out[(3 * 4 + 3) * 4 + 3], 255); // abajo derecha: se queda
  });
}
