import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
import '../../notes/domain/note_block.dart';
import '../../settings/settings.dart';
import '../../summary/application/summary_runner.dart';
import '../../transcription/application/segment_merger.dart';
import '../../../core/platform_info.dart';

/// Exportar e importar audios.
class AudioTools {
  /// Comprime el WAV a M4A (mucho más liviano para enviar). Si no se puede,
  /// devuelve el WAV original.
  ///
  /// Con [enhance]: quita zumbidos graves y ruido de fondo (aire, ventilador),
  /// comprime un poco para que se oiga parejo quien habla lejos y cerca, y
  /// sube el volumen a un nivel normal.
  static Future<String> toM4a(String wavPath, {bool enhance = false}) async {
    final out = p.join((await getTemporaryDirectory()).path,
        '${p.basenameWithoutExtension(wavPath)}${enhance ? '-mejorado' : ''}.m4a');
    final args = [
      '-y', '-i', wavPath,
      if (enhance) ...['-af', enhanceFilter, '-ar', '44100'],
      '-c:a', 'aac', '-b:a', enhance ? '128k' : '96k', out,
    ];
    if (!isPhone) {
      if (await _desktopFfmpeg(args)) return out;
      // Sin filtros si el ffmpeg de la compu no los tiene.
      if (enhance) return toM4a(wavPath);
      return wavPath;
    }
    try {
      final session = await FFmpegKit.executeWithArguments(args);
      if (ReturnCode.isSuccess(await session.getReturnCode()) && File(out).existsSync()) {
        return out;
      }
    } catch (_) {}
    if (enhance) return toM4a(wavPath);
    return wavPath;
  }

  /// Copia limpia del audio (sin ruido, volumen parejo) en WAV mono 16 kHz,
  /// para volver a transcribir. null si no se pudo.
  static Future<String?> enhancedWav16k(String input) async {
    final out = p.join((await getTemporaryDirectory()).path, '${p.basenameWithoutExtension(input)}-limpio.wav');
    final args = ['-y', '-i', input, '-af', enhanceFilter, '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', out];
    if (!isPhone) return await _desktopFfmpeg(args) ? out : null;
    try {
      final session = await FFmpegKit.executeWithArguments(args);
      if (ReturnCode.isSuccess(await session.getReturnCode()) && File(out).existsSync()) return out;
    } catch (_) {}
    return null;
  }

  /// Filtros de "audio mejorado" para voz.
  static const enhanceFilter = 'highpass=f=90,'
      'afftdn=nr=12:nf=-30:tn=1,'
      'acompressor=threshold=-22dB:ratio=3:attack=10:release=200:makeup=2,'
      'loudnorm=I=-16:TP=-1.5:LRA=11,'
      'alimiter=limit=0.95';

  /// Convierte cualquier audio (mp3, m4a, ogg, opus de WhatsApp…) a WAV mono
  /// de 16 kHz, el formato que necesita Whisper.
  static Future<String?> toWav16k(String input, String output) async {
    if (!isPhone) {
      return await _desktopFfmpeg(['-y', '-i', input, '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', output])
          ? output
          : null;
    }
    final session =
        await FFmpegKit.execute('-y -i "$input" -ar 16000 -ac 1 -c:a pcm_s16le "$output"');
    final ok = ReturnCode.isSuccess(await session.getReturnCode());
    return ok && File(output).existsSync() ? output : null;
  }

  /// En la compu se usa el ffmpeg instalado (si lo hay).
  static Future<bool> _desktopFfmpeg(List<String> args) async {
    try {
      final r = await Process.run('ffmpeg', args);
      return r.exitCode == 0 && File(args.last).existsSync();
    } catch (_) {
      return false;
    }
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

enum AudioExport { audio, audioEnhanced, transcript, summary, all }

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

  if (what == AudioExport.audio || what == AudioExport.audioEnhanced || what == AudioExport.all) {
    final audio = await AudioTools.toM4a(block.path, enhance: what == AudioExport.audioEnhanced);
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
