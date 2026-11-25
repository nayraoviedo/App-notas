import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/camera/camera_service.dart';
import '../features/notes/data/notes_repository.dart';
import '../features/notes/domain/note.dart';
import '../features/notes/domain/note_block.dart';
import '../features/speakers/data/speakers_repository.dart';
import '../features/speakers/domain/speaker.dart';
import '../features/speakers/domain/voice_embedder.dart';
import '../features/transcription/data/whisper_transcription_service.dart';
import '../features/transcription/domain/transcript_segment.dart';
import '../features/transcription/domain/transcription_service.dart';
import 'database/app_database.dart';
import 'files/file_storage.dart';

// ------------------------------------------------------------ Infraestructura

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final fileStorageProvider = Provider<FileStorage>((ref) => FileStorage());

final notesRepositoryProvider =
    Provider<NotesRepository>((ref) => NotesRepository(ref.watch(databaseProvider)));

final speakersRepositoryProvider = Provider<SpeakersRepository>(
    (ref) => SpeakersRepository(ref.watch(databaseProvider)));

final cameraServiceProvider =
    Provider<CameraService>((ref) => CameraService(ref.watch(fileStorageProvider)));

/// Cambia aquí el motor de transcripción (local o en la nube).
final transcriptionServiceProvider =
    Provider<TranscriptionService>((ref) => WhisperTranscriptionService());

/// Cambia aquí a la implementación con sherpa_onnx cuando esté lista.
final voiceEmbedderProvider =
    Provider<VoiceEmbedder>((ref) => const NoopVoiceEmbedder());

// ------------------------------------------------------------------ Datos

final notesListProvider = StreamProvider<List<Note>>(
    (ref) => ref.watch(notesRepositoryProvider).watchNotes());

final noteProvider = StreamProvider.family<Note?, String>(
    (ref, id) => ref.watch(notesRepositoryProvider).watchNote(id));

final blocksProvider = StreamProvider.family<List<NoteBlock>, String>(
    (ref, noteId) => ref.watch(notesRepositoryProvider).watchBlocks(noteId));

final segmentsProvider = StreamProvider.family<List<TranscriptSegment>, String>(
    (ref, blockId) => ref.watch(notesRepositoryProvider).watchSegments(blockId));

final markersProvider = StreamProvider.family<List<int>, String>(
    (ref, blockId) => ref.watch(notesRepositoryProvider).watchMarkers(blockId));

final speakersProvider = StreamProvider<List<Speaker>>(
    (ref) => ref.watch(speakersRepositoryProvider).watchAll());
