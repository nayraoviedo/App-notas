import 'dart:io';
import 'dart:typed_data';

import 'package:app_notas/features/recording/data/pcm_resample.dart';
import 'package:app_notas/features/recording/data/wav_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('48 kHz → 16 kHz: un tercio de muestras, promedio y cabecera correcta', () async {
    final ds = Downsampler3();
    final b = ByteData(8 * 2);
    for (var i = 0; i < 8; i++) {
      b.setInt16(i * 2, i * 30, Endian.little);
    }
    final out = ds.add(b.buffer.asUint8List());
    expect(out.length, 4); // 2 muestras; sobran 2 para la próxima
    expect(ByteData.sublistView(out).getInt16(0, Endian.little), 30);

    final dir = await Directory.systemTemp.createTemp('kumo');
    final w = WavWriter('${dir.path}/a.wav', sampleRate: 48000);
    await w.open();
    w.add(Uint8List(48000 * 2)); // 1 s
    await w.close();
    expect(wavSampleRate('${dir.path}/a.wav'), 48000);
    final o = await wav48To16('${dir.path}/a.wav', '${dir.path}/b.wav');
    expect(wavSampleRate(o), 16000);
    expect(File(o).lengthSync(), 44 + 16000 * 2);
  });
}
