import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/files/app_dirs.dart';
import '../../../core/providers.dart';
import '../../recording/application/audio_tools.dart';
import '../../settings/settings.dart';
import '../../transcription/data/groq_transcription.dart';
import '../../transcription/domain/transcript_segment.dart';
import '../../transcription/domain/transcription_service.dart';
import '../data/video_backend.dart';

/// Transcripción de un video (se guarda en un archivo por video).
///
/// - Video propio o enlace directo: se saca el audio y se transcribe como
///   una grabación (Groq → Gemini → en el teléfono).
/// - YouTube: Gemini puede "ver" videos públicos de YouTube por su enlace
///   (necesita la clave de Gemini en Ajustes).
class VideoTranscripts {
  static Future<File> _file(String source) async {
    final dir = Directory(p.join((await appDataDir()).path, 'video_transcripts'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final id = sha1.convert(utf8.encode(source)).toString();
    return File(p.join(dir.path, '$id.json'));
  }

  static Future<List<TranscriptSegment>?> load(String source) async {
    final f = await _file(source);
    if (!f.existsSync()) return null;
    try {
      return [
        for (final m in (jsonDecode(await f.readAsString()) as List).cast<Map>())
          TranscriptSegment(startMs: (m['s'] as num).toInt(), endMs: (m['e'] as num).toInt(), text: m['t'] as String),
      ];
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(String source, List<TranscriptSegment> segs) async {
    final f = await _file(source);
    await f.writeAsString(jsonEncode([
      for (final s in segs) {'s': s.startMs, 'e': s.endMs, 't': s.text},
    ]));
  }

  static Future<List<TranscriptSegment>> transcribe(
    WidgetRef ref,
    String source, {
    void Function(String status)? onStatus,
  }) async {
    final settings = ref.read(settingsProvider);
    final lang = settings.language;
    List<TranscriptSegment> segs;
    if (isYoutubeUrl(source)) {
      final key = (await ref.read(apiKeysProvider).read(AiProvider.gemini) ?? '').trim();
      if (key.isEmpty) {
        throw TranscriptionException('Para transcribir videos de YouTube pon tu clave de Gemini en Ajustes '
            '(es gratis en aistudio.google.com).');
      }
      onStatus?.call('Gemini está escuchando el video de YouTube… (puede tardar unos minutos)');
      segs = await GeminiTranscriber(apiKey: key, model: settings.geminiModel).transcribe(source, lang: lang);
    } else {
      onStatus?.call('Sacando el audio del video…');
      final wav = p.join((await getTemporaryDirectory()).path, 'video_${DateTime.now().millisecondsSinceEpoch}.wav');
      final ok = await AudioTools.toWav16k(source, wav);
      if (ok == null) throw TranscriptionException('No se pudo sacar el audio de este video.');
      try {
        final service = ref.read(transcriptionServiceProvider);
        if (!await service.isModelReady()) {
          await service.ensureModel(onProgress: (pc) => onStatus?.call('Bajando el modelo de voz… $pc%'));
        }
        onStatus?.call('Transcribiendo…');
        segs = await service.transcribeFile(wav, lang: lang, onProgress: (pc) => onStatus?.call('Transcribiendo… $pc%'));
      } finally {
        try {
          await File(wav).delete();
        } catch (_) {}
      }
    }
    if (segs.isEmpty) throw TranscriptionException('No se escuchó voz en este video.');
    await _save(source, segs);
    return segs;
  }
}
