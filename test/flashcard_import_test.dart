import 'package:app_notas/features/study/domain/flashcard_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('una tarjeta por línea con punto y coma, tabulación, | y ::', () {
    final r = parseFlashcards('¿Capital de Bolivia? ; Sucre\n'
        'Mitosis\tDivisión celular\n'
        '2 + 2 | 4\n'
        'H2O :: Agua\n');
    expect(r.cards, const [
      ImportedCard('¿Capital de Bolivia?', 'Sucre'),
      ImportedCard('Mitosis', 'División celular'),
      ImportedCard('2 + 2', '4'),
      ImportedCard('H2O', 'Agua'),
    ]);
    expect(r.skipped, isEmpty);
  });

  test('bloques P: / R: con respuesta de varias líneas', () {
    final r = parseFlashcards('P: ¿Qué es la fotosíntesis?\n'
        'R: Proceso de las plantas\n'
        'con la luz del sol.\n'
        '\n'
        'Pregunta: ¿Y la célula?\n'
        'Respuesta: La unidad de la vida.\n');
    expect(r.cards, const [
      ImportedCard('¿Qué es la fotosíntesis?', 'Proceso de las plantas\ncon la luz del sol.'),
      ImportedCard('¿Y la célula?', 'La unidad de la vida.'),
    ]);
  });

  test('CSV con comillas, encabezado y comentarios', () {
    final r = parseFlashcards('pregunta;respuesta\r\n'
        '# tema 1\r\n'
        '"¿Año de la independencia?","1825"\r\n'
        '"Dice ""hola""; ¿en inglés?",hello\r\n');
    expect(r.cards, const [
      ImportedCard('¿Año de la independencia?', '1825'),
      ImportedCard('Dice "hola"; ¿en inglés?', 'hello'),
    ]);
  });

  test('las líneas sin separador se avisan', () {
    final r = parseFlashcards('Hola ; mundo\nesto no tiene separador\n');
    expect(r.cards.length, 1);
    expect(r.skipped, ['esto no tiene separador']);
  });

  test('P: con la respuesta en la misma línea', () {
    final r = parseFlashcards('P: ¿Capital de Perú? ; R: Lima');
    expect(r.cards, const [ImportedCard('¿Capital de Perú?', 'Lima')]);
  });
}
