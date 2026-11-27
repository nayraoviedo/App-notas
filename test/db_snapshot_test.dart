import 'dart:io';

import 'package:app_notas/core/database/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('la foto de la base (VACUUM INTO) trae los cambios recientes', () async {
    final tmp = Directory.systemTemp.createTempSync('kumo-db');
    final db = AppDatabase(NativeDatabase(File(p.join(tmp.path, 'app_notas.sqlite')),
        setup: (raw) => raw.execute('PRAGMA journal_mode = WAL')));
    await db.into(db.notes).insert(NotesCompanion.insert(
        id: 'n1', title: const Value('Clase de hoy'), createdAt: DateTime(2026), updatedAt: DateTime(2026)));
    final dest = p.join(tmp.path, 'foto.sqlite');
    // Lo mismo que hace la app antes de cada copia (app.dart).
    await db.customStatement('VACUUM INTO ?', [dest]);
    await db.close();

    final copy = AppDatabase(NativeDatabase(File(dest)));
    final notes = await copy.select(copy.notes).get();
    expect(notes.map((n) => n.title), ['Clase de hoy']);
    await copy.close();
    tmp.deleteSync(recursive: true);
  });
}
