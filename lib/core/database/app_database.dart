import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// Base de datos local. Después de cambiar las tablas ejecuta:
/// `dart run build_runner build --delete-conflicting-outputs`
@DriftDatabase(
  tables: [
    Notebooks,
    Notes,
    Blocks,
    Speakers,
    TranscriptSegments,
    Markers,
    Summaries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'app_notas'));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(notebooks);
            await m.addColumn(notes, notes.notebookId);
            await m.addColumn(blocks, blocks.fontFamily);
            await m.addColumn(blocks, blocks.fontSize);
          }
          if (from < 3) {
            await m.createTable(summaries);
          }
          if (from < 4) {
            await m.addColumn(notebooks, notebooks.coverStyle);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
