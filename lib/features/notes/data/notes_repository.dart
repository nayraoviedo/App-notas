import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../transcription/domain/transcript_segment.dart';
import '../domain/note.dart';
import '../domain/note_block.dart';

class NotesRepository {
  NotesRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // ---------------------------------------------------------------- Notas

  /// Notas de un cuaderno, o todas si [notebookId] es null.
  Stream<List<Note>> watchNotes({String? notebookId}) {
    final q = _db.select(_db.notes)
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);
    if (notebookId != null) q.where((n) => n.notebookId.equals(notebookId));
    return q.watch().map((rows) => rows.map(_toNote).toList());
  }

  Stream<Note?> watchNote(String id) {
    final q = _db.select(_db.notes)..where((n) => n.id.equals(id));
    return q.watchSingleOrNull().map((r) => r == null ? null : _toNote(r));
  }

  Future<String> createNote(
      {String title = '', String? notebookId, List<String> tags = const []}) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.into(_db.notes).insert(NotesCompanion.insert(
          id: id,
          title: Value(title),
          notebookId: Value(notebookId),
          tags: Value(tags.join('|')),
          createdAt: now,
          updatedAt: now,
        ));
    return id;
  }

  Future<void> renameNote(String id, String title) =>
      (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(title: Value(title), updatedAt: Value(DateTime.now())),
      );

  Future<void> moveToNotebook(String noteId, String? notebookId) =>
      (_db.update(_db.notes)..where((n) => n.id.equals(noteId)))
          .write(NotesCompanion(notebookId: Value(notebookId)));

  /// Borra la nota y todo lo que cuelga de ella. Devuelve las rutas de los
  /// archivos (audios, fotos, hojas) para que se borren del disco.
  ///
  /// El borrado en cascada se hace a mano: con versiones muy nuevas de Dart,
  /// drift_dev puede omitir las claves foráneas (REFERENCES) al generar código.
  Future<List<String>> deleteNote(String id) {
    return _db.transaction(() async {
      final blocks =
          await (_db.select(_db.blocks)..where((b) => b.noteId.equals(id))).get();
      final ids = blocks.map((b) => b.id).toList();
      await _deleteBlockChildren(ids);
      await (_db.delete(_db.blocks)..where((b) => b.noteId.equals(id))).go();
      await (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
      return [for (final b in blocks) if (b.filePath != null) b.filePath!];
    });
  }

  Future<void> _deleteBlockChildren(List<String> blockIds) async {
    if (blockIds.isEmpty) return;
    await (_db.delete(_db.transcriptSegments)..where((s) => s.blockId.isIn(blockIds))).go();
    await (_db.delete(_db.markers)..where((m) => m.blockId.isIn(blockIds))).go();
    await (_db.delete(_db.summaries)..where((s) => s.blockId.isIn(blockIds))).go();
  }

  Future<void> _touch(String noteId) =>
      (_db.update(_db.notes)..where((n) => n.id.equals(noteId)))
          .write(NotesCompanion(updatedAt: Value(DateTime.now())));

  // --------------------------------------------------------------- Bloques

  Stream<List<NoteBlock>> watchBlocks(String noteId) {
    final q = _db.select(_db.blocks)
      ..where((b) => b.noteId.equals(noteId))
      ..orderBy([(b) => OrderingTerm.asc(b.position)]);
    return q.watch().map((rows) => rows.map(_toBlock).nonNulls.toList());
  }

  Future<int> _nextPosition(String noteId) async {
    final maxPos = _db.blocks.position.max();
    final q = _db.selectOnly(_db.blocks)
      ..addColumns([maxPos])
      ..where(_db.blocks.noteId.equals(noteId));
    final row = await q.getSingle();
    return (row.read(maxPos) ?? -1) + 1;
  }

  Future<String> _insertBlock(String noteId, BlocksCompanion data) async {
    final id = _uuid.v4();
    final position = await _nextPosition(noteId);
    await _db.into(_db.blocks).insert(data.copyWith(
          id: Value(id),
          noteId: Value(noteId),
          position: Value(position),
          createdAt: Value(DateTime.now()),
        ));
    await _touch(noteId);
    return id;
  }

  Future<String> addTextBlock(String noteId, {String text = ''}) =>
      _insertBlock(
        noteId,
        BlocksCompanion(type: const Value('text'), textContent: Value(text)),
      );

  Future<void> updateText(String blockId, String text) =>
      (_db.update(_db.blocks)..where((b) => b.id.equals(blockId)))
          .write(BlocksCompanion(textContent: Value(text)));

  Future<void> updateTextStyle(String blockId,
          {required String? fontFamily, required double? fontSize}) =>
      (_db.update(_db.blocks)..where((b) => b.id.equals(blockId))).write(
        BlocksCompanion(fontFamily: Value(fontFamily), fontSize: Value(fontSize)),
      );

  Future<void> updateMarks(String blockId, List<TextMark> marks) =>
      (_db.update(_db.blocks)..where((b) => b.id.equals(blockId))).write(
        BlocksCompanion(marks: Value(marks.isEmpty ? null : TextMark.encode(marks))),
      );

  Future<void> updateTextColor(String blockId, int? color) =>
      (_db.update(_db.blocks)..where((b) => b.id.equals(blockId)))
          .write(BlocksCompanion(textColor: Value(color)));

  /// Cambia la foto de un bloque (por ejemplo, después de recortarla).
  Future<void> updateImagePath(String blockId, String path) =>
      (_db.update(_db.blocks)..where((b) => b.id.equals(blockId)))
          .write(BlocksCompanion(filePath: Value(path)));

  Future<String> addImageBlock(String noteId, String path,
          {MediaAnchor? anchor}) =>
      _insertBlock(
        noteId,
        BlocksCompanion(
          type: const Value('image'),
          filePath: Value(path),
          anchorBlockId: Value(anchor?.audioBlockId),
          anchorVideoPath: Value(anchor?.videoPath),
          anchorMs: Value(anchor?.atMs),
        ),
      );

  Future<String> addDrawingBlock(String noteId, String path) => _insertBlock(
        noteId,
        BlocksCompanion(type: const Value('drawing'), filePath: Value(path)),
      );

  /// Inserta una hoja justo después de [afterBlockId] (para "agregar página"
  /// y "copiar página" dentro del cuaderno).
  Future<String> insertDrawingBlockAfter(
      String noteId, String afterBlockId, String path) {
    return _db.transaction(() async {
      final after = await (_db.select(_db.blocks)
            ..where((b) => b.id.equals(afterBlockId)))
          .getSingle();
      await (_db.update(_db.blocks)
            ..where((b) =>
                b.noteId.equals(noteId) & b.position.isBiggerThanValue(after.position)))
          .write(BlocksCompanion.custom(position: _db.blocks.position + const Constant(1)));
      final id = _uuid.v4();
      await _db.into(_db.blocks).insert(BlocksCompanion.insert(
            id: id,
            noteId: noteId,
            position: after.position + 1,
            type: 'drawing',
            filePath: Value(path),
            createdAt: DateTime.now(),
          ));
      await _touch(noteId);
      return id;
    });
  }

  Future<String> addVideoRefBlock(
    String noteId, {
    required String videoPath,
    required int atMs,
    required String text,
  }) =>
      _insertBlock(
        noteId,
        BlocksCompanion(
          type: const Value('videoRef'),
          textContent: Value(text),
          anchorVideoPath: Value(videoPath),
          anchorMs: Value(atMs),
        ),
      );

  /// Guarda una grabación con su transcripción y sus marcas "Importante"
  /// en una sola transacción.
  Future<String> addAudioBlock(
    String noteId, {
    required String path,
    required int durationMs,
    required List<TranscriptSegment> segments,
    required List<AudioMarker> markers,
  }) {
    return _db.transaction(() async {
      final blockId = await _insertBlock(
        noteId,
        BlocksCompanion(
          type: const Value('audio'),
          filePath: Value(path),
          durationMs: Value(durationMs),
        ),
      );
      await _db.batch((b) {
        b.insertAll(
          _db.transcriptSegments,
          segments.map((s) => TranscriptSegmentsCompanion.insert(
                blockId: blockId,
                startMs: s.startMs,
                endMs: s.endMs,
                content: s.text,
                speakerId: Value(s.speakerId),
              )),
        );
        b.insertAll(
          _db.markers,
          markers.map((m) => MarkersCompanion.insert(
              blockId: blockId, atMs: m.atMs, label: Value(m.label))),
        );
      });
      return blockId;
    });
  }

  /// Reemplaza la transcripción de una grabación (para transcribir de nuevo).
  Future<void> replaceSegments(String blockId, List<TranscriptSegment> segments) =>
      _db.transaction(() async {
        await (_db.delete(_db.transcriptSegments)..where((t) => t.blockId.equals(blockId))).go();
        await _db.batch((b) {
          b.insertAll(
            _db.transcriptSegments,
            segments.map((s) => TranscriptSegmentsCompanion.insert(
                  blockId: blockId,
                  startMs: s.startMs,
                  endMs: s.endMs,
                  content: s.text,
                  speakerId: Value(s.speakerId),
                )),
          );
        });
      });

  Future<void> deleteBlock(String blockId) => _db.transaction(() async {
        await _deleteBlockChildren([blockId]);
        await (_db.delete(_db.blocks)..where((b) => b.id.equals(blockId))).go();
      });

  // ---------------------------------------------------- Transcripciones

  Stream<List<TranscriptSegment>> watchSegments(String blockId) {
    final q = _db.select(_db.transcriptSegments)
      ..where((s) => s.blockId.equals(blockId))
      ..orderBy([(s) => OrderingTerm.asc(s.startMs)]);
    return q.watch().map((rows) => rows
        .map((r) => TranscriptSegment(
              id: r.id,
              startMs: r.startMs,
              endMs: r.endMs,
              text: r.content,
              speakerId: r.speakerId,
            ))
        .toList());
  }

  Future<void> updateSegmentText(int segmentId, String text) =>
      (_db.update(_db.transcriptSegments)..where((s) => s.id.equals(segmentId)))
          .write(TranscriptSegmentsCompanion(content: Value(text)));

  Future<void> updateSegmentSpeaker(int segmentId, String? speakerId) =>
      (_db.update(_db.transcriptSegments)..where((s) => s.id.equals(segmentId)))
          .write(TranscriptSegmentsCompanion(speakerId: Value(speakerId)));

  Stream<List<AudioMarker>> watchMarkers(String blockId) {
    final q = _db.select(_db.markers)
      ..where((m) => m.blockId.equals(blockId))
      ..orderBy([(m) => OrderingTerm.asc(m.atMs)]);
    return q.watch().map((rows) => rows
        .map((r) => AudioMarker(id: r.id, atMs: r.atMs, label: r.label))
        .toList());
  }

  /// Nota rápida (o ⭐ si [label] es null) agregada después de grabar.
  Future<void> addMarker(String blockId, int atMs, {String? label}) => _db
      .into(_db.markers)
      .insert(MarkersCompanion.insert(blockId: blockId, atMs: atMs, label: Value(label)));

  Future<void> updateMarker(int id, String label) =>
      (_db.update(_db.markers)..where((m) => m.id.equals(id)))
          .write(MarkersCompanion(label: Value(label)));

  Future<void> deleteMarker(int id) =>
      (_db.delete(_db.markers)..where((m) => m.id.equals(id))).go();

  // ---------------------------------------------------------- Resúmenes

  Stream<SummaryRow?> watchSummary(String blockId) =>
      (_db.select(_db.summaries)..where((s) => s.blockId.equals(blockId)))
          .watchSingleOrNull();

  Future<void> saveSummary(SummariesCompanion data) =>
      _db.into(_db.summaries).insertOnConflictUpdate(data);

  // ---------------------------------------------------------- Búsqueda

  /// Busca en títulos, texto de bloques y en lo que se dijo en los audios.
  /// TODO: pasar a FTS5 cuando haya muchas notas.
  Future<List<SearchHit>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final pattern = '%$q%';
    final hits = <SearchHit>[];

    final titleRows = await (_db.select(_db.notes)
          ..where((n) => n.title.like(pattern)))
        .get();
    for (final n in titleRows) {
      hits.add(SearchHit(noteId: n.id, noteTitle: n.title, snippet: n.title));
    }

    final blockQuery = _db.select(_db.blocks).join([
      innerJoin(_db.notes, _db.notes.id.equalsExp(_db.blocks.noteId)),
    ])
      ..where(_db.blocks.textContent.like(pattern));
    for (final row in await blockQuery.get()) {
      final b = row.readTable(_db.blocks);
      final n = row.readTable(_db.notes);
      hits.add(SearchHit(
        noteId: n.id,
        noteTitle: n.title,
        snippet: b.textContent ?? '',
        blockId: b.id,
        atMs: b.anchorMs,
      ));
    }

    final segQuery = _db.select(_db.transcriptSegments).join([
      innerJoin(_db.blocks,
          _db.blocks.id.equalsExp(_db.transcriptSegments.blockId)),
      innerJoin(_db.notes, _db.notes.id.equalsExp(_db.blocks.noteId)),
    ])
      ..where(_db.transcriptSegments.content.like(pattern));
    for (final row in await segQuery.get()) {
      final s = row.readTable(_db.transcriptSegments);
      final n = row.readTable(_db.notes);
      hits.add(SearchHit(
        noteId: n.id,
        noteTitle: n.title,
        snippet: s.content,
        blockId: s.blockId,
        atMs: s.startMs,
      ));
    }
    return hits;
  }

  // ---------------------------------------------------------- Mapeos

  Note _toNote(NoteRow r) => Note(
        id: r.id,
        title: r.title,
        notebookId: r.notebookId,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        tags: decodeTags(r.tags),
      );

  static List<String> decodeTags(String raw) =>
      raw.split('|').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  // -------------------------------------------------------------- Etiquetas

  Future<void> setTags(String noteId, List<String> tags) =>
      (_db.update(_db.notes)..where((n) => n.id.equals(noteId))).write(NotesCompanion(
        tags: Value(tags.map((t) => t.replaceAll('|', ' ').trim()).where((t) => t.isNotEmpty).toSet().join('|')),
      ));

  /// Todas las etiquetas usadas, ordenadas.
  Stream<List<String>> watchAllTags() => _db.select(_db.notes).watch().map((rows) {
        final all = <String>{for (final r in rows) ...decodeTags(r.tags)};
        return all.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      });

  /// Cambia el nombre de una etiqueta en todas las notas (o la quita si
  /// [to] es null).
  Future<void> renameTag(String from, String? to) => _db.transaction(() async {
        final rows = await _db.select(_db.notes).get();
        for (final r in rows) {
          final tags = decodeTags(r.tags);
          if (!tags.contains(from)) continue;
          final next = [for (final t in tags) if (t != from) t, if (to != null && to.trim().isNotEmpty) to.trim()];
          await setTags(r.id, next);
        }
      });

  NoteBlock? _toBlock(BlockRow r) {
    switch (r.type) {
      case 'text':
        return TextBlock(
          id: r.id,
          position: r.position,
          text: r.textContent ?? '',
          fontFamily: r.fontFamily,
          fontSize: r.fontSize,
          marks: TextMark.decode(r.marks),
          textColor: r.textColor,
        );
      case 'audio':
        return AudioBlock(
          id: r.id,
          position: r.position,
          path: r.filePath!,
          durationMs: r.durationMs ?? 0,
        );
      case 'image':
        MediaAnchor? anchor;
        if (r.anchorBlockId != null) {
          anchor = MediaAnchor.audio(
              audioBlockId: r.anchorBlockId!, atMs: r.anchorMs ?? 0);
        } else if (r.anchorVideoPath != null) {
          anchor = MediaAnchor.video(
              videoPath: r.anchorVideoPath!, atMs: r.anchorMs ?? 0);
        }
        return ImageBlock(
            id: r.id, position: r.position, path: r.filePath!, anchor: anchor);
      case 'drawing':
        return DrawingBlock(id: r.id, position: r.position, path: r.filePath!);
      case 'videoRef':
        return VideoRefBlock(
          id: r.id,
          position: r.position,
          videoPath: r.anchorVideoPath!,
          atMs: r.anchorMs ?? 0,
          text: r.textContent ?? '',
        );
    }
    return null;
  }
}
