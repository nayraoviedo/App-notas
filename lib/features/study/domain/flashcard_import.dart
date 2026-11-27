/// Importar preguntas y respuestas a tarjetas desde texto pegado o un
/// archivo .txt / .csv.
///
/// Formatos que entiende (se pueden mezclar):
///
/// 1. Una tarjeta por línea, con la pregunta y la respuesta separadas por
///    punto y coma, tabulación (lo que sale al copiar de Excel o Google
///    Sheets, o al exportar de Anki/Quizlet), barra `|` o dos puntos dobles `::`:
///
///        ¿Capital de Bolivia? ; Sucre
///        Mitosis | División de una célula en dos iguales
///
/// 2. Bloques con "P:" y "R:" (o "Pregunta:" / "Respuesta:"); la respuesta
///    puede ocupar varias líneas hasta la siguiente "P:":
///
///        P: ¿Qué es la fotosíntesis?
///        R: Proceso con el que las plantas
///        hacen su alimento con la luz.
///
/// Las líneas vacías y las que empiezan con `#` se ignoran. Si el texto viene
/// de un CSV con comas (con o sin comillas), también se lee.
library;

class ImportedCard {
  const ImportedCard(this.front, this.back);
  final String front;
  final String back;

  @override
  bool operator ==(Object other) => other is ImportedCard && other.front == front && other.back == back;

  @override
  int get hashCode => Object.hash(front, back);

  @override
  String toString() => 'ImportedCard($front → $back)';
}

class FlashcardImportResult {
  const FlashcardImportResult(this.cards, this.skipped);
  final List<ImportedCard> cards;

  /// Líneas que no se pudieron leer (sin separador), para avisar.
  final List<String> skipped;
}

final _qPrefix = RegExp(r'^\s*(p|q|pregunta|question)\s*[:.)\-]\s*', caseSensitive: false);
final _aPrefix = RegExp(r'^\s*(r|a|respuesta|answer)\s*[:.)\-]\s*', caseSensitive: false);

FlashcardImportResult parseFlashcards(String text) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final cards = <ImportedCard>[];
  final skipped = <String>[];

  // Bloque P:/R: en curso.
  String? q;
  final a = StringBuffer();
  var inAnswer = false;
  void flush() {
    if (q != null && q!.trim().isNotEmpty) {
      cards.add(ImportedCard(q!.trim(), a.toString().trim()));
    }
    q = null;
    a.clear();
    inAnswer = false;
  }

  // CSV con comas y sin comillas ("pregunta,respuesta"): solo si ninguna
  // línea usa otro separador y casi todas tienen una coma (así una pregunta
  // con coma en un archivo con ";" no se corta mal).
  final comma = _commaMode(lines);

  for (var raw in lines) {
    if (raw.startsWith('\uFEFF')) raw = raw.substring(1);
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      // Una línea vacía cierra un bloque solo si ya tiene respuesta.
      if (inAnswer) flush();
      continue;
    }
    if (line.trimLeft().startsWith('#')) continue;

    if (_qPrefix.hasMatch(line)) {
      flush();
      final rest = line.replaceFirst(_qPrefix, '');
      final pair = _splitLine(rest, comma: comma);
      if (pair != null && pair.$1.isNotEmpty) {
        // "P: pregunta ; respuesta" en una sola línea.
        cards.add(ImportedCard(pair.$1, pair.$2.replaceFirst(_aPrefix, '')));
      } else {
        q = rest;
      }
      continue;
    }
    if (q != null && _aPrefix.hasMatch(line) && !inAnswer) {
      inAnswer = true;
      a.write(line.replaceFirst(_aPrefix, ''));
      continue;
    }
    if (q != null) {
      // Continuación de la pregunta o de la respuesta.
      if (inAnswer) {
        a.write('\n${line.trim()}');
      } else {
        q = '${q!}\n${line.trim()}';
      }
      continue;
    }

    final pair = _splitLine(line, comma: comma);
    if (pair == null) {
      skipped.add(line.trim());
    } else if (pair.$1.isNotEmpty) {
      cards.add(ImportedCard(pair.$1, pair.$2));
    }
  }
  flush();

  // Si la primera fila es un encabezado tipo "pregunta;respuesta", se quita.
  if (cards.isNotEmpty && _isHeader(cards.first)) cards.removeAt(0);
  return FlashcardImportResult(cards, skipped);
}

bool _isHeader(ImportedCard c) {
  final f = c.front.toLowerCase();
  final b = c.back.toLowerCase();
  return {'pregunta', 'preguntas', 'frente', 'question', 'front'}.contains(f) &&
      {'respuesta', 'respuestas', 'reverso', 'answer', 'back'}.contains(b);
}

/// Divide una línea en (pregunta, respuesta) por el primer separador que
/// aparezca, en orden de preferencia. Devuelve null si no hay ninguno.
(String, String)? _splitLine(String line, {bool comma = false}) {
  if (line.contains('\t')) return _cut(line, '\t');
  final csv = _csvPair(line);
  if (csv != null) return csv;
  for (final sep in const [';', '|', '::']) {
    if (line.contains(sep)) return _cut(line, sep);
  }
  if (comma && line.contains(',')) return _cut(line, ',');
  return null;
}

bool _commaMode(List<String> lines) {
  var rows = 0, withComma = 0;
  for (final raw in lines) {
    final l = raw.trim();
    if (l.isEmpty || l.startsWith('#') || l.startsWith('"')) continue;
    if (_qPrefix.hasMatch(l) || _aPrefix.hasMatch(l)) return false;
    if (l.contains('\t') || l.contains(';') || l.contains('|') || l.contains('::')) return false;
    rows++;
    if (l.contains(',')) withComma++;
  }
  return rows > 0 && withComma >= rows * 0.8;
}

(String, String) _cut(String line, String sep) {
  final i = line.indexOf(sep);
  return (_unquote(line.substring(0, i)), _unquote(line.substring(i + sep.length)));
}

String _unquote(String s) {
  var t = s.trim();
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
    t = t.substring(1, t.length - 1).replaceAll('""', '"').trim();
  }
  return t;
}

/// Lee una fila CSV entre comillas: "pregunta","respuesta" (o con ;).
(String, String)? _csvPair(String line) {
  final t = line.trim();
  if (!t.startsWith('"')) return null;
  final fields = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < t.length; i++) {
    final ch = t[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < t.length && t[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cur.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',' || ch == ';') {
      fields.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  fields.add(cur.toString().trim());
  if (fields.length < 2) return null;
  return (fields[0], fields.sublist(1).where((f) => f.isNotEmpty).join('\n'));
}
