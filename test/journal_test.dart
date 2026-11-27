import 'dart:ui';

import 'package:app_notas/features/drawing/domain/canvas_item.dart';
import 'package:app_notas/features/journal/domain/journal.dart';
import 'package:app_notas/features/study/domain/cornell.dart';
import 'package:app_notas/features/summary/domain/summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ánimo y nota del día se guardan y se leen', () {
    final d = DateTime(2026, 11, 25);
    final st = const JournalState().setDay(d, const DayEntry(mood: Mood.great, text: 'Hola'));
    final back = JournalState.decode(st.encode());
    expect(back.day(d).mood, Mood.great);
    expect(back.day(d).text, 'Hola');
    expect(back.moodCounts(2026, 11), {Mood.great: 1});
    expect(back.setDay(d, const DayEntry()).days, isEmpty);
  });

  test('racha de hábitos', () {
    final today = DateTime(2026, 11, 25);
    var st = const JournalState(habits: [Habit(id: 'h', name: 'Agua')]);
    for (final i in [1, 2, 3, 5]) {
      st = st.toggle('h', DateTime(2026, 11, 25 - i));
    }
    expect(st.streak('h', today), 3); // hoy aún no: cuenta desde ayer
    st = st.toggle('h', today);
    expect(st.streak('h', today), 4);
    st = st.toggle('h', today);
    expect(st.isDone('h', today), isFalse);
    expect(weekStart(today).weekday, DateTime.monday);
  });

  test('resumen a hoja Cornell (y sigue en otra hoja si no entra)', () {
    Size measure(TextItem t) => Size(t.width, (t.text.length / 30 + 1) * t.size * 1.3);
    final s = TranscriptSummary(
      title: 'Biología',
      overview: 'La célula se divide.',
      chapters: [
        for (var i = 0; i < 30; i++)
          Chapter(atMs: i * 60000, title: 'Tema $i', summary: 'Explicación larga del tema $i ' * 4),
      ],
    );
    final pages = cornellPages(s, measure: measure);
    expect(pages.length, greaterThan(1));
    final items = pages.first.layers.first.items.whereType<TextItem>().toList();
    expect(items.first.text, 'Biología');
    expect(items.any((t) => t.text.startsWith('Resumen:')), isTrue);
    for (final p in pages) {
      for (final t in p.layers.first.items.whereType<TextItem>()) {
        expect(t.y, lessThan(p.height));
      }
    }
  });
}
