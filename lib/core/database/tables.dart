import 'package:drift/drift.dart';

/// Una nota: contenedor de bloques ordenados.
@DataClassName('NoteRow')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Un bloque de una nota. `type` es: text | audio | image | videoRef.
///
/// Las columnas `anchor*` sirven para "anclar" un bloque a un momento de un
/// audio o de un video (por ejemplo, una foto tomada mientras se grababa o una
/// captura de video).
@DataClassName('BlockRow')
class Blocks extends Table {
  TextColumn get id => text()();
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get type => text()();

  /// Texto del bloque (texto libre o comentario en un videoRef).
  TextColumn get textContent => text().nullable()();

  /// Archivo en disco (audio .wav, imagen, video).
  TextColumn get filePath => text().nullable()();
  IntColumn get durationMs => integer().nullable()();

  /// Bloque de audio al que está anclado (fotos tomadas durante una grabación).
  TextColumn get anchorBlockId => text().nullable()();

  /// Video al que está anclado (capturas y notas de video).
  TextColumn get anchorVideoPath => text().nullable()();

  /// Momento del audio/video al que apunta el ancla.
  IntColumn get anchorMs => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Personas detectadas o nombradas en las grabaciones.
@DataClassName('SpeakerRow')
class Speakers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// "Huella" de voz (vector float32) para reconocer a la persona después.
  BlobColumn get embedding => blob().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Fragmentos de transcripción de un bloque de audio.
@DataClassName('SegmentRow')
class TranscriptSegments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get blockId =>
      text().references(Blocks, #id, onDelete: KeyAction.cascade)();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
  TextColumn get content => text()();
  TextColumn get speakerId => text().nullable().references(Speakers, #id)();
}

/// Momentos marcados como "Importante" durante una grabación.
@DataClassName('MarkerRow')
class Markers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get blockId =>
      text().references(Blocks, #id, onDelete: KeyAction.cascade)();
  IntColumn get atMs => integer()();
  TextColumn get label => text().nullable()();
}
