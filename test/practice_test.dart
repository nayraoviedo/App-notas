import 'package:app_notas/features/drawing/application/practice_builder.dart';
import 'package:app_notas/features/drawing/domain/drawing.dart';
import 'package:app_notas/features/drawing/domain/practice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('los caracteres escritos se separan y se ignora la puntuación', () {
    final chars = charsFromText('学习，中文! ');
    expect(chars.map((c) => c.char), ['学', '习', '中', '文']);
  });

  test('muchos caracteres se reparten en varias páginas', () {
    final sheet = PracticeSheet(chars: charsFromText('一二三四五六七八九十人口大小山水火木日月'));
    final pages = buildPracticePages(sheet);
    expect(pages.length, greaterThan(1));
    final total = pages.fold<int>(0, (n, p) => n + p.paper.practice!.chars.length);
    expect(total, 20);
  });

  test('sin caracteres crea una cuadrícula vacía', () {
    final pages = buildPracticePages(const PracticeSheet(chars: []));
    expect(pages, hasLength(1));
    expect(pages.single.paper.practice!.chars, isEmpty);
  });

  test('la práctica se guarda y se lee igual (JSON)', () {
    final d = buildPracticePages(PracticeSheet(
      chars: practiceSets.first.chars,
      grid: PracticeGrid.mizi,
      traceCount: 5,
    )).first;
    final back = Drawing.fromJson(d.toJson());
    final p = back.paper.practice!;
    expect(p.grid, PracticeGrid.mizi);
    expect(p.traceCount, 5);
    expect(p.chars.first.pinyin, 'yī');
  });

  test('todos los ejemplos traen pinyin y significado', () {
    for (final set in practiceSets) {
      for (final c in set.chars) {
        expect(c.pinyin, isNotNull, reason: c.char);
        expect(c.meaning, isNotNull, reason: c.char);
      }
    }
  });
}
