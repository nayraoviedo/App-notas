import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
import '../../notes/domain/note_block.dart';
import '../../settings/settings.dart';
import '../../summary/application/summary_runner.dart';
import '../../transcription/application/segment_merger.dart';

/// Exportar e importar audios.
class AudioTools {
  /// Comprime el WAV a M4A (mucho más liviano para enviar). Si no se puede,
  /// devuelve el WAV original.
  static Future<String> toM4a(String wavPath) async {
    final out = p.join(Directory.systemTemp.path, '${p.basenameWithoutExtension(wavPath)}.m4a');
    try {
      final session = await FFmpegKit.execute('-y -i "$wavPath" -c:a aac -b:a 96k "$out"');
      if (ReturnCode.isSuccess(await session.getReturnCode()) && File(out).existsSync()) {
        return out;
      }
    } catch (_) {}
    return wavPath;
  }

  /// Convierte cualquier audio (mp3, m4a, ogg, opus de WhatsApp…) a WAV mono
  /// de 16 kHz, el formato que necesita Whisper.
  static Future<String?> toWav16k(String input, String output) async {
    final session =
        await FFmpegKit.execute('-y -i "$input" -ar 16000 -ac 1 -c:a pcm_s16le "$output"');
    final ok = ReturnCode.isSuccess(await session.getReturnCode());
    return ok && File(output).existsSync() ? output : null;
  }

  /// Duración de un WAV PCM16 mono 16 kHz a partir de su tamaño.
  static int wavDurationMs(String path) {
    final bytes = File(path).lengthSync() - 44;
    return bytes <= 0 ? 0 : bytes * 1000 ~/ (16000 * 2);
  }
}

/// Texto plano con la transcripción (minuto, quién habla y texto) y las
/// notas rápidas.
Future<String> transcriptAsText(WidgetRef ref, String blockId, {String title = ''}) async {
  final segments = await ref.read(segmentsProvider(blockId).future);
  final markers = await ref.read(markersProvider(blockId).future);
  final speakers = {for (final s in await ref.read(speakersProvider.future)) s.id: s.name};
  final b = StringBuffer();
  if (title.isNotEmpty) b..writeln(title)..writeln();
  for (final s in segments) {
    final who = s.speakerId == null ? '' : '${speakers[s.speakerId] ?? ''}: ';
    b.writeln('[${formatMs(s.startMs)}] $who${s.text}');
  }
  final notes = markers.where((m) => m.isQuickNote).toList();
  if (notes.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Notas rápidas:');
    for (final m in notes) {
      b.writeln('[${formatMs(m.atMs)}] ${m.label}');
    }
  }
  return b.toString();
}

Future<String> summaryAsText(WidgetRef ref, String blockId) async {
  final s = await ref.read(summaryProvider(blockId).future);
  if (s == null) return '';
  final b = StringBuffer()
    ..writeln(s.title)
    ..writeln()
    ..writeln(s.overview);
  if (s.keyPoints.isNotEmpty) {
    b.writeln('\nPuntos clave:');
    for (final k in s.keyPoints) {
      b.writeln('• $k');
    }
  }
  if (s.chapters.isNotEmpty) {
    b.writeln('\nCapítulos:');
    for (final c in s.chapters) {
      b.writeln('[${formatMs(c.atMs)}] ${c.title}\n${c.summary}\n');
    }
  }
  if (s.tasks.isNotEmpty) {
    b.writeln('Tareas:');
    for (final t in s.tasks) {
      b.writeln('☐ ${t.task}${t.due == null ? '' : ' (${t.due})'}');
    }
  }
  return b.toString();
}

Future<String> _writeTemp(String name, String content) async {
  final path = p.join(Directory.systemTemp.path, name);
  await File(path).writeAsString(content);
  return path;
}

String _safe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();

enum AudioExport { audio, transcript, summary, all }

/// Comparte la grabación, la transcripción y/o el resumen (WhatsApp, Drive,
/// correo, etc.).
Future<void> shareRecording(
  WidgetRef ref,
  AudioBlock block, {
  required String title,
  required AudioExport what,
}) async {
  final name = _safe(title.isEmpty ? 'Grabación' : title);
  final files = <XFile>[];

  if (what == AudioExport.audio || what == AudioExport.all) {
    final audio = await AudioTools.toM4a(block.path);
    files.add(XFile(audio, name: '$name${p.extension(audio)}'));
  }
  if (what == AudioExport.transcript || what == AudioExport.all) {
    final text = await transcriptAsText(ref, block.id, title: title);
    files.add(XFile(await _writeTemp('$name - transcripción.txt', text)));
  }
  if (what == AudioExport.summary || what == AudioExport.all) {
    final text = await summaryAsText(ref, block.id);
    if (text.isNotEmpty) files.add(XFile(await _writeTemp('$name - resumen.txt', text)));
  }
  if (files.isEmpty) return;
  await SharePlus.instance.share(ShareParams(files: files, subject: title));
}

/// Importa un audio (mp3, m4a, ogg, opus de WhatsApp, wav…), lo transcribe
/// con Whisper y lo agrega a la nota como una grabación más.
Future<String?> importAudio(
  WidgetRef ref,
  String noteId, {
  void Function(String status)? onStatus,
}) async {
  final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
  final input = picked?.files.single.path;
  if (input == null) return null;

  onStatus?.call('Convirtiendo el audio…');
  final storage = ref.read(fileStorageProvider);
  final wav = await AudioTools.toWav16k(input, await storage.newAudioPath());
  if (wav == null) throw Exception('No se pudo leer ese archivo de audio');

  final service = ref.read(transcriptionServiceProvider);
  if (!await service.isModelReady()) {
    onStatus?.call('Descargando el modelo de voz (solo la primera vez)…');
    await service.ensureModel(
        onProgress: (p) => onStatus?.call('Descargando el modelo de voz… $p%'));
  }
  onStatus?.call('Transcribiendo… (puede tardar unos minutos)');
  final settings = ref.read(settingsProvider);
  final raw = await ref.read(transcriptionServiceProvider).transcribeFile(
        wav,
        lang: settings.language,
        onProgress: (pct) => onStatus?.call('Transcribiendo… $pct%'),
      );
  final paragraphs = const SegmentMerger().merge(raw, const []);

  return ref.read(notesRepositoryProvider).addAudioBlock(
        noteId,
        path: wav,
        durationMs: AudioTools.wavDurationMs(wav),
        segments: paragraphs,
        markers: const [],
      );
}
