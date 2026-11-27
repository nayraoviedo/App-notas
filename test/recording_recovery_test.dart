import 'dart:io';
import 'dart:typed_data';

import 'package:app_notas/features/recording/application/recording_recovery.dart';
import 'package:app_notas/features/recording/data/wav_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arregla la cabecera de un WAV que quedó a medias', () async {
    final dir = await Directory.systemTemp.createTemp('kumo_rec');
    final path = '${dir.path}/a.wav';
    final w = WavWriter(path);
    await w.open();
    // Escribir 3 s sin cerrar (como si la app se cerrara de golpe).
    w.add(Uint8List(16000 * 2 * 3));
    final dataLen = fixWavHeader(File(path), 16000);
    expect(dataLen, 16000 * 2 * 3);
    final h = ByteData.sublistView(File(path).readAsBytesSync().sublist(0, 44));
    expect(h.getUint32(40, Endian.little), dataLen);
    expect(h.getUint32(24, Endian.little), 16000);
    expect(recordingJournalPath(path), endsWith('.wav.grabando.json'));
  });
}
