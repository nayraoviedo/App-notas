import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../core/providers.dart';
import '../../notes/domain/note_block.dart';
import '../../speakers/application/speaker_tracker.dart';
import '../../speakers/domain/speaker.dart';
import '../../settings/settings.dart';
import '../../speakers/domain/voice_embedder.dart';
import '../../transcription/application/segment_merger.dart';
import '../../transcription/domain/transcript_segment.dart';
import '../../transcription/domain/transcription_service.dart';
import '../data/wav_writer.dart';
import '../../../core/platform_info.dart';
import '../data/pcm_resample.dart';

enum RecordingStatus { idle, recording, paused, processing, done, error }

class PendingPhoto {
  const PendingPhoto(this.path, this.atMs);
  final String path;
  final int atMs;
}

class RecordingState {
  const RecordingState({
    this.status = RecordingStatus.idle,
    this.elapsedMs = 0,
    this.liveText = '',
    this.markers = const [],
    this.photos = const [],
    this.pendingSpeakerChange,
    this.currentSpeakerId,
    this.progress = 0,
    this.progressLabel,
    this.message,
    this.micBlocked = false,
    this.savedBlockId,
    this.levels = const [],
  });

  /// Volumen reciente (0–1), para dibujar la onda mientras se graba.
  final List<double> levels;

  /// Bloque de audio ya guardado de la última grabación (para abrirlo).
  final String? savedBlockId;

  final RecordingStatus status;
  final int elapsedMs;
  final String liveText;
  final List<AudioMarker> markers;
  final List<PendingPhoto> photos;
  final SpeakerChangeSuggestion? pendingSpeakerChange;
  final String? currentSpeakerId;

  /// Progreso de la transcripción final (0–100).
  final int progress;

  /// Qué se está haciendo al terminar ("Descargando el modelo de voz…").
  final String? progressLabel;
  final String? message;

  /// Permiso del micrófono negado (o bloqueado en Ajustes).
  final bool micBlocked;

  bool get isActive =>
      status == RecordingStatus.recording || status == RecordingStatus.paused;

  RecordingState copyWith({
    RecordingStatus? status,
    int? elapsedMs,
    String? liveText,
    List<AudioMarker>? markers,
    List<PendingPhoto>? photos,
    SpeakerChangeSuggestion? pendingSpeakerChange,
    bool clearPending = false,
    String? currentSpeakerId,
    int? progress,
    String? progressLabel,
    String? message,
    bool? micBlocked,
    String? savedBlockId,
    List<double>? levels,
  }) =>
      RecordingState(
        status: status ?? this.status,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        liveText: liveText ?? this.liveText,
        markers: markers ?? this.markers,
        photos: photos ?? this.photos,
        pendingSpeakerChange: clearPending
            ? null
            : (pendingSpeakerChange ?? this.pendingSpeakerChange),
        currentSpeakerId: currentSpeakerId ?? this.currentSpeakerId,
        progress: progress ?? this.progress,
        progressLabel: progressLabel ?? this.progressLabel,
        message: message ?? this.message,
        micBlocked: micBlocked ?? this.micBlocked,
        savedBlockId: savedBlockId ?? this.savedBlockId,
        levels: levels ?? this.levels,
      );
}

/// Orquesta una grabación: micrófono → archivo WAV + transcripción en vivo +
/// detección de cambio de voz. Al terminar transcribe el archivo completo,
/// arma párrafos por hablante y guarda todo en la nota.
class RecordingController extends Notifier<RecordingState> {
  AudioRecorder? _recorder;
  WavWriter? _wav;
  SpeakerTracker? _tracker;
  LiveTranscription? _live;
  StreamSubscription<Uint8List>? _pcmSub;
  StreamSubscription<Uint8List>? _pcm16Sub;
  StreamSubscription<String>? _liveSub;
  StreamSubscription<SpeakerChangeSuggestion>? _suggestionSub;
  Timer? _ticker;
  String? _noteId;
  String _lang = 'es';

  final _levels = <double>[];
  double _peak = 0;

  /// Términos que Whisper debe escribir bien (idea: vocabulario por materia).
  List<String> vocabulary = const [];


  @override
  RecordingState build() => const RecordingState();

  Future<void> start(String noteId) async {
    if (state.isActive) return;
    final settings = ref.read(settingsProvider);
    final autoSpeakerDetection = settings.autoSpeakerDetection;
    final liveTranscription = settings.liveTranscription;
    _lang = settings.language;
    state = const RecordingState();
    _noteId = noteId;

    // Pedir el permiso del micrófono. Si se negó "para siempre", Android ya no
    // muestra el aviso: hay que activarlo desde Ajustes.
    var mic = PermissionStatus.granted;
    if (isPhone) {
      mic = await Permission.microphone.status;
      if (!mic.isGranted) mic = await Permission.microphone.request();
    }
    if (!mic.isGranted) {
      state = state.copyWith(
        status: RecordingStatus.error,
        micBlocked: mic.isPermanentlyDenied || mic.isRestricted,
        message: mic.isPermanentlyDenied
            ? 'El micrófono está bloqueado para la app. Actívalo en Ajustes → '
                'Permisos → Micrófono.'
            : 'Para grabar, la app necesita permiso para usar el micrófono.',
      );
      return;
    }
    final recorder = AudioRecorder();
    _recorder = recorder;

    final path = await ref.read(fileStorageProvider).newAudioPath();
    // Alta calidad: se guarda a 48 kHz; para transcribir y detectar voces
    // se baja a 16 kHz al vuelo.
    final hq = ref.read(sharedPreferencesProvider).getBool('record.hq') ?? false;
    final rate = hq ? 48000 : 16000;
    _wav = WavWriter(path, sampleRate: rate);
    await _wav!.open();

    // La detección de voz se prepara en segundo plano: la primera vez descarga
    // el modelo. Mientras tanto se graba normal y se puede marcar a mano.
    final embedder = ref.read(voiceEmbedderProvider);
    if (autoSpeakerDetection) {
      unawaited(embedder.prepare().catchError((Object _) {
        state = state.copyWith(
            message: 'Detección de voz no disponible (sin internet para '
                'descargar el modelo). Puedes marcar quién habla a mano.');
      }));
    }

    final known = await ref.read(speakersRepositoryProvider).getAll();
    _tracker = SpeakerTracker(
      autoSpeakerDetection ? embedder : const NoopVoiceEmbedder(),
      knownSpeakers: {
        for (final s in known)
          if (s.embedding != null) s.id: s.embedding!,
      },
    );
    _suggestionSub = _tracker!.suggestions.listen(
      (s) => state = state.copyWith(pendingSpeakerChange: s),
    );

    final raw = (await recorder.startStream(RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: rate,
      numChannels: 1,
    )))
        .asBroadcastStream();
    final ds = hq ? Downsampler3() : null;
    final pcm = ds == null ? raw : raw.map(ds.add).asBroadcastStream();

    _levels.clear();
    _pcmSub = raw.listen((bytes) {
      _wav?.add(bytes);
      _peak = math.max(_peak, pcmLevel(bytes));
    });
    _pcm16Sub = pcm.listen((bytes) => _tracker?.addPcm16(bytes));

    _ticker = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (state.status == RecordingStatus.recording) {
        _levels.add(_peak);
        if (_levels.length > 64) _levels.removeAt(0);
      }
      _peak = 0;
      state = state.copyWith(elapsedMs: _wav?.durationMs ?? 0, levels: List.of(_levels));
    });
    state = state.copyWith(status: RecordingStatus.recording);

    if (liveTranscription) {
      try {
        _live = await ref.read(transcriptionServiceProvider).startLive(pcm, lang: _lang);
        _liveSub = _live!.partials
            .listen((text) => state = state.copyWith(liveText: text));
      } catch (_) {
        // Si el teléfono no puede con la transcripción en vivo, se sigue
        // grabando y se transcribe todo al final.
        state = state.copyWith(
            message: 'La transcripción en vivo empieza cuando esté listo el modelo de voz; '
                'igual se transcribe todo al terminar.');
      }
    }
  }

  Future<void> pause() async {
    if (state.status != RecordingStatus.recording) return;
    await _recorder?.pause();
    state = state.copyWith(status: RecordingStatus.paused);
  }

  Future<void> resume() async {
    if (state.status != RecordingStatus.paused) return;
    await _recorder?.resume();
    state = state.copyWith(status: RecordingStatus.recording);
  }

  /// Botón "⭐ Importante".
  void addMarker() {
    if (!state.isActive) return;
    state = state.copyWith(markers: [...state.markers, AudioMarker(atMs: state.elapsedMs)]);
  }

  /// Nota rápida escrita mientras se graba, pegada al minuto [atMs]
  /// (el momento en que se empezó a escribir).
  void addQuickNote(String text, {required int atMs}) {
    if (text.trim().isEmpty) return;
    state = state.copyWith(
        markers: [...state.markers, AudioMarker(atMs: atMs, label: text.trim())]);
  }

  /// Foto sincronizada con el minuto actual de la grabación.
  /// [capture] abre la cámara y devuelve la ruta temporal de la foto.
  Future<void> takePhoto(Future<String?> Function() capture) async {
    if (!state.isActive) return;
    final atMs = _wav?.durationMs ?? state.elapsedMs;
    final temp = await capture();
    if (temp == null) return;
    final path = await ref.read(cameraServiceProvider).savePhoto(temp);
    state = state.copyWith(photos: [...state.photos, PendingPhoto(path, atMs)]);
  }

  // ------------------------------------------------------------ Hablantes

  /// "Ahora habla X". En los primeros 3 s cuenta como quien empieza.
  void setCurrentSpeaker(String speakerId) {
    final atMs = state.elapsedMs < 3000 ? 0 : state.elapsedMs;
    _tracker?.markTurn(speakerId, atMs);
    state = state.copyWith(currentSpeakerId: speakerId, clearPending: true);
  }

  Future<void> confirmSpeaker(String speakerId) async {
    final embedding = _tracker?.confirm(speakerId);
    if (embedding != null) {
      await ref
          .read(speakersRepositoryProvider)
          .saveEmbedding(speakerId, embedding);
    }
    state = state.copyWith(currentSpeakerId: speakerId, clearPending: true);
  }

  Future<void> confirmNewSpeaker(String name) async {
    final id = await ref.read(speakersRepositoryProvider).create(name);
    await confirmSpeaker(id);
  }

  void dismissSpeakerChange() {
    _tracker?.dismiss();
    state = state.copyWith(clearPending: true);
  }

  // ------------------------------------------------------------- Terminar

  Future<void> stop() async {
    if (!state.isActive) return;
    final noteId = _noteId!;
    state = state.copyWith(status: RecordingStatus.processing, clearPending: true);

    _ticker?.cancel();
    // Cada paso con tiempo límite: si la transcripción en vivo o el
    // micrófono se traban, igual se guarda el audio.
    Future<void> safe(Future<void>? Function() f) async {
      try {
        await f()?.timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    await safe(() => _recorder?.stop());
    await safe(() => _pcmSub?.cancel());
    await safe(() => _pcm16Sub?.cancel());
    await safe(() => _live?.stop());
    await safe(() => _liveSub?.cancel());
    await safe(() => _wav?.close());

    final wav = _wav!;
    final turns = List.of(_tracker?.turns ?? const <SpeakerTurn>[]);
    final markers = state.markers;
    final photos = state.photos;
    final liveText = state.liveText.trim();

    // 1) Guardar el audio YA (con el texto en vivo, si hubo), para que nunca
    //    se pierda aunque la transcripción tarde, falle o se cierre la app.
    final repo = ref.read(notesRepositoryProvider);
    final String blockId;
    try {
      blockId = await repo.addAudioBlock(
      noteId,
      path: wav.path,
      durationMs: wav.durationMs,
      segments: [
        if (liveText.isNotEmpty)
          TranscriptSegment(startMs: 0, endMs: wav.durationMs, text: liveText),
      ],
      markers: markers,
    );
    } catch (e) {
      await _cleanupSafe();
      state = state.copyWith(
          status: RecordingStatus.done, message: 'No se pudo guardar la grabación: $e');
      return;
    }
    state = state.copyWith(savedBlockId: blockId);
    for (final photo in photos) {
      await repo.addImageBlock(
        noteId,
        photo.path,
        anchor: MediaAnchor.audio(audioBlockId: blockId, atMs: photo.atMs),
      );
    }
    await _cleanupSafe();

    // 2) Transcribir con calma y reemplazar el texto provisional.
    String? message;
    final service = ref.read(transcriptionServiceProvider);
    try {
      if (!await service.isModelReady()) {
        state = state.copyWith(
            progress: 0,
            progressLabel: 'Audio guardado ✔\nDescargando el modelo de voz (solo la primera vez)…');
        await service.ensureModel(onProgress: (p) => state = state.copyWith(progress: p));
      }
      state = state.copyWith(
          progress: 0, progressLabel: 'Audio guardado ✔\nTranscribiendo y ordenando por párrafos…');
      final segments = await service.transcribeFile(
        wav.path,
        lang: _lang,
        vocabulary: vocabulary,
        onProgress: (p) => state = state.copyWith(progress: p),
      );
      if (segments.isEmpty) {
        message = 'No se escuchó voz en la grabación (o fue muy bajita). El audio quedó guardado.';
      } else {
        await repo.replaceSegments(blockId, const SegmentMerger().merge(segments, turns));
      }
    } on TranscriptionException catch (e) {
      message = '${e.message}\nEl audio quedó guardado: ábrelo y toca "Transcribir ahora".';
    } catch (e) {
      message = 'No se pudo transcribir ($e), pero el audio quedó guardado.';
    }
    state = state.copyWith(status: RecordingStatus.done, message: message);
  }

  /// Descarta la grabación en curso.
  Future<void> cancel() async {
    _ticker?.cancel();
    await _recorder?.stop();
    await _live?.stop();
    await _liveSub?.cancel();
    await _pcmSub?.cancel();
    await _pcm16Sub?.cancel();
    await _wav?.close();
    final storage = ref.read(fileStorageProvider);
    await storage.deleteIfExists(_wav?.path);
    for (final p in state.photos) {
      await storage.deleteIfExists(p.path);
    }
    await _cleanup();
    state = const RecordingState();
  }

  Future<void> _cleanupSafe() async {
    try {
      await _cleanup().timeout(const Duration(seconds: 5));
    } catch (_) {
      _recorder = null;
      _tracker = null;
      _live = null;
      _liveSub = null;
      _pcmSub = null;
      _pcm16Sub = null;
      _suggestionSub = null;
      _ticker = null;
    }
  }

  Future<void> _cleanup() async {
    await _suggestionSub?.cancel();
    await _tracker?.dispose();
    await _recorder?.dispose();
    _recorder = null;
    _tracker = null;
    _live = null;
    _liveSub = null;
    _pcmSub = null;
    _pcm16Sub = null;
    _suggestionSub = null;
    _ticker = null;
  }
}

/// Volumen de un trozo de audio PCM16 (0 = silencio, 1 = muy fuerte).
double pcmLevel(Uint8List bytes) {
  if (bytes.length < 2) return 0;
  final data = ByteData.sublistView(bytes);
  var sum = 0.0;
  final n = bytes.length ~/ 2;
  for (var i = 0; i < n; i += 4) {
    final v = data.getInt16(i * 2, Endian.little) / 32768.0;
    sum += v * v;
  }
  final rms = math.sqrt(sum / ((n + 3) ~/ 4));
  // Escala logarítmica suave para que la voz normal se vea.
  return (math.log(1 + rms * 60) / math.log(61)).clamp(0.0, 1.0);
}

final recordingControllerProvider =
    NotifierProvider<RecordingController, RecordingState>(RecordingController.new);
