import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/speaker.dart';

class SpeakersRepository {
  SpeakersRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Speaker>> watchAll() => (_db.select(_db.speakers)
        ..orderBy([(s) => OrderingTerm.asc(s.name)]))
      .watch()
      .map((rows) => rows.map(_toSpeaker).toList());

  Future<List<Speaker>> getAll() async =>
      (await _db.select(_db.speakers).get()).map(_toSpeaker).toList();

  Future<String> create(String name, {List<double>? embedding}) async {
    final id = _uuid.v4();
    await _db.into(_db.speakers).insert(SpeakersCompanion.insert(
          id: id,
          name: name,
          embedding: Value(embedding == null ? null : _encode(embedding)),
          createdAt: DateTime.now(),
        ));
    return id;
  }

  Future<void> rename(String id, String name) =>
      (_db.update(_db.speakers)..where((s) => s.id.equals(id)))
          .write(SpeakersCompanion(name: Value(name)));

  Future<void> saveEmbedding(String id, List<double> embedding) =>
      (_db.update(_db.speakers)..where((s) => s.id.equals(id)))
          .write(SpeakersCompanion(embedding: Value(_encode(embedding))));

  Speaker _toSpeaker(SpeakerRow r) => Speaker(
        id: r.id,
        name: r.name,
        embedding: r.embedding == null ? null : _decode(r.embedding!),
      );

  static Uint8List _encode(List<double> v) =>
      Float32List.fromList(v).buffer.asUint8List();

  // Se copia para garantizar alineación de 4 bytes.
  static List<double> _decode(Uint8List bytes) =>
      Float32List.view(Uint8List.fromList(bytes).buffer).toList();
}
