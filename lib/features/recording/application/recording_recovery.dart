import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/files/app_dirs.dart';
import '../../notes/data/notes_repository.dart';
import '../../notes/domain/note_block.dart';

/// Diario de una grabación en curso (junto al .wav). Si existe al abrir la
/// app, es que la grabación no llegó a guardarse (Android cerró Kumo, se
/// apagó el celular…): se recupera.
String recordingJournalPath(String wavPath) => '$wavPath.grabando.json';

/// Recupera las grabaciones que quedaron a medias: arregla el .wav, lo pone
/// en su nota (o en una nota nueva si se borró) con sus notas ⭐ y fotos.
/// Devuelve los ids de las notas donde quedaron.
Future<List<String>> recoverInterruptedRecordings(NotesRepository repo) async {
  final dir = Directory(p.join((await appDataDir()).path, 'audio'));
  if (!dir.existsSync()) return const [];
  final notes = <String>[];
  for (final j in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.grabando.json'))) {
    final wav = File(j.path.substring(0, j.path.length - '.grabando.json'.length));
    try {
      // Si el audio se tocó hace muy poco, quizá se sigue grabando: no tocar.
      if (wav.existsSync() && DateTime.now().difference(wav.lastModifiedSync()).inSeconds < 30) continue;
      final info = jsonDecode(j.readAsStringSync()) as Map<String, Object?>;
      if (!wav.existsSync() || wav.lengthSync() <= 44 + 3200) {
        // Nada que recuperar (menos de un instante de audio).
        if (wav.existsSync()) wav.deleteSync();
        j.deleteSync();
        continue;
      }
      if (await repo.fileInUse(wav.path)) {
        j.deleteSync(); // ya estaba guardada
        continue;
      }
      final rate = (info['rate'] as num?)?.toInt() ?? 16000;
      final dataLen = fixWavHeader(wav, rate);
      final durationMs = dataLen * 1000 ~/ (rate * 2);

      var noteId = info['noteId'] as String?;
      if (noteId == null || !await repo.noteExists(noteId)) {
        final at = DateTime.fromMillisecondsSinceEpoch(
            (info['startedAt'] as num?)?.toInt() ?? wav.lastModifiedSync().millisecondsSinceEpoch);
        noteId = await repo.createNote(title: 'Grabación recuperada ${at.day}/${at.month}');
      }
      final markers = [
        for (final m in (info['markers'] as List? ?? const []).cast<Map>())
          if (((m['at'] as num?)?.toInt() ?? 0) <= durationMs)
            AudioMarker(atMs: (m['at'] as num?)?.toInt() ?? 0, label: m['label'] as String?),
      ];
      final blockId = await repo.addAudioBlock(
        noteId,
        path: wav.path,
        durationMs: durationMs,
        segments: const [],
        markers: markers,
      );
      for (final ph in (info['photos'] as List? ?? const []).cast<Map>()) {
        final path = ph['path'] as String?;
        if (path == null || !File(path).existsSync()) continue;
        await repo.addImageBlock(
          noteId,
          path,
          anchor: MediaAnchor.audio(audioBlockId: blockId, atMs: (ph['at'] as num?)?.toInt() ?? 0),
        );
      }
      j.deleteSync();
      notes.add(noteId);
    } catch (_) {
      // Se intenta de nuevo la próxima vez.
    }
  }
  return notes;
}

/// Pone en la cabecera del WAV el tamaño real del audio (si la app se
/// cerró, puede haber quedado desactualizada). Devuelve los bytes de audio.
int fixWavHeader(File wav, int rate) {
  final f = wav.openSync(mode: FileMode.append);
  try {
    final total = f.lengthSync();
    var dataLen = total - 44;
    if (dataLen.isOdd) dataLen -= 1;
    final b = ByteData(4);
    f.setPositionSync(4);
    b.setUint32(0, 36 + dataLen, Endian.little);
    f.writeFromSync(b.buffer.asUint8List());
    f.setPositionSync(24);
    b.setUint32(0, rate, Endian.little);
    f.writeFromSync(b.buffer.asUint8List());
    f.setPositionSync(28);
    b.setUint32(0, rate * 2, Endian.little);
    f.writeFromSync(b.buffer.asUint8List());
    f.setPositionSync(40);
    b.setUint32(0, dataLen, Endian.little);
    f.writeFromSync(b.buffer.asUint8List());
    return dataLen;
  } finally {
    f.closeSync();
  }
}
