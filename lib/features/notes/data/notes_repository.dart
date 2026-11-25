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

  Stream<List<Note>> watchNotes() {
    final q = _db.select(_db.notes)
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);
    return q.watch().map((rows) => rows.map(_toNote).toList());
  }

  Stream<Note?> watchNote(String id) {
    final q = _db.select(_db.notes)..where((n) => n.id.equals(id));
    return q.watchSingleOrNull().map((r) => r == null ? null : _toNote(r));
  }

  Future<String> createNote({String title = ''}) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.into(_db.notes).insert(NotesCompanion.insert(
          id: id,
          title: Value(title),
          createdAt: now,
          updatedAt: now,
        ));
    return id;
  }

  Future<void> renameNote(String id, String title) =>
      (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(title: Value(title), updatedAt: Value(DateTime.now())),
      );

  Future<void> deleteNote(String id) =>
      (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();

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
    required List<int> markersMs,
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
          markersMs.map(
              (ms) => MarkersCompanion.insert(blockId: blockId, atMs: ms)),
        );
      });
      return blockId;
    });
  }

  Future<void> deleteBlock(String blockId) =>
      (_db.delete(_db.blocks)..where((b) => b.id.equals(blockId))).go();

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

  Stream<List<int>> watchMarkers(String blockId) {
    final q = _db.select(_db.markers)
      ..where((m) => m.blockId.equals(blockId))
      ..orderBy([(m) => OrderingTerm.asc(m.atMs)]);
    return q.watch().map((rows) => rows.map((r) => r.atMs).toList());
  }

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
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      );

  NoteBlock? _toBlock(BlockRow r) {
    switch (r.type) {
      case 'text':
        return TextBlock(id: r.id, position: r.position, text: r.textContent ?? '');
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
