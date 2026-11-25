import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/recording/application/audio_tools.dart';
import '../features/transcription/data/groq_transcription.dart';

import '../features/camera/camera_service.dart';
import '../features/drawing/data/drawing_store.dart';
import '../features/drawing/domain/drawing.dart';
import '../features/importing/import_service.dart';
import '../features/notebooks/data/notebooks_repository.dart';
import '../features/settings/settings.dart';
import '../features/notebooks/domain/notebook.dart';
import '../features/notes/data/notes_repository.dart';
import '../features/notes/domain/note.dart';
import '../features/notes/domain/note_block.dart';
import '../features/speakers/data/sherpa_voice_embedder.dart';
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

final notebooksRepositoryProvider = Provider<NotebooksRepository>(
    (ref) => NotebooksRepository(ref.watch(databaseProvider)));

final speakersRepositoryProvider = Provider<SpeakersRepository>(
    (ref) => SpeakersRepository(ref.watch(databaseProvider)));

final cameraServiceProvider = Provider<CameraService>((ref) => CameraService(
      ref.watch(fileStorageProvider),
      ref.watch(sharedPreferencesProvider),
    ));

/// Cambia aquí el motor de transcripción (local o en la nube).
/// Con clave de Groq transcribe en la nube (rápido); si no, en el teléfono.
final transcriptionServiceProvider = Provider<TranscriptionService>((ref) => SmartTranscriptionService(
      local: WhisperTranscriptionService(),
      groqKey: () => ref.read(apiKeysProvider).read(AiProvider.groq),
      compress: AudioTools.toM4a,
    ));

/// Huella de voz para detectar cambios de hablante. Usa `NoopVoiceEmbedder()`
/// para apagar la detección automática.
final voiceEmbedderProvider = Provider<VoiceEmbedder>((ref) {
  final embedder = SherpaVoiceEmbedder();
  ref.onDispose(embedder.dispose);
  return embedder;
});

final drawingStoreProvider = Provider<DrawingStore>((ref) => DrawingStore());

final importServiceProvider = Provider<ImportService>((ref) => ImportService(
      ref.watch(fileStorageProvider),
      ref.watch(drawingStoreProvider),
      ref.watch(notesRepositoryProvider),
    ));

// ------------------------------------------------------------------ Datos

/// Hoja de dibujo cargada desde su archivo (para la vista previa en la nota).
final drawingFileProvider = FutureProvider.autoDispose.family<Drawing, String>(
    (ref, path) => ref.watch(drawingStoreProvider).load(path));

/// Notas de un cuaderno (null = todas).
final notesListProvider = StreamProvider.family<List<Note>, String?>((ref, notebookId) =>
    ref.watch(notesRepositoryProvider).watchNotes(notebookId: notebookId));

final allTagsProvider =
    StreamProvider<List<String>>((ref) => ref.watch(notesRepositoryProvider).watchAllTags());

final notebooksProvider = StreamProvider<List<Notebook>>(
    (ref) => ref.watch(notebooksRepositoryProvider).watchAll());

final notebookProvider = StreamProvider.family<Notebook?, String>(
    (ref, id) => ref.watch(notebooksRepositoryProvider).watch(id));

final notebookCountsProvider = StreamProvider<Map<String, int>>(
    (ref) => ref.watch(notebooksRepositoryProvider).watchCounts());

final noteProvider = StreamProvider.family<Note?, String>(
    (ref, id) => ref.watch(notesRepositoryProvider).watchNote(id));

final blocksProvider = StreamProvider.family<List<NoteBlock>, String>(
    (ref, noteId) => ref.watch(notesRepositoryProvider).watchBlocks(noteId));

final segmentsProvider = StreamProvider.family<List<TranscriptSegment>, String>(
    (ref, blockId) => ref.watch(notesRepositoryProvider).watchSegments(blockId));

final markersProvider = StreamProvider.family<List<AudioMarker>, String>(
    (ref, blockId) => ref.watch(notesRepositoryProvider).watchMarkers(blockId));

final speakersProvider = StreamProvider<List<Speaker>>(
    (ref) => ref.watch(speakersRepositoryProvider).watchAll());
