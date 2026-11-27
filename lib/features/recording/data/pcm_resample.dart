import 'dart:io';
import 'dart:typed_data';

/// Baja PCM16 mono de 48 kHz a 16 kHz (promedio de cada 3 muestras: hace de
/// filtro simple y alcanza para voz). [carry] guarda las muestras que
/// sobran entre pedazos del stream.
class Downsampler3 {
  final _carry = <int>[];

  Uint8List add(Uint8List bytes) {
    final inSamples = ByteData.sublistView(bytes);
    final all = <int>[..._carry];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      all.add(inSamples.getInt16(i, Endian.little));
    }
    final n = all.length ~/ 3;
    final out = ByteData(n * 2);
    for (var k = 0; k < n; k++) {
      final v = (all[3 * k] + all[3 * k + 1] + all[3 * k + 2]) ~/ 3;
      out.setInt16(k * 2, v, Endian.little);
    }
    _carry
      ..clear()
      ..addAll(all.sublist(n * 3));
    return out.buffer.asUint8List();
  }
}

/// Frecuencia de muestreo de un WAV (lee la cabecera), o null.
int? wavSampleRate(String path) {
  try {
    final f = File(path).openSync();
    final h = f.readSync(28);
    f.closeSync();
    if (h.length < 28 || String.fromCharCodes(h.sublist(0, 4)) != 'RIFF') return null;
    return ByteData.sublistView(h).getUint32(24, Endian.little);
  } catch (_) {
    return null;
  }
}

/// Copia un WAV PCM16 mono de 48 kHz a 16 kHz (sin ffmpeg). Devuelve [out].
Future<String> wav48To16(String path, String out) async {
  final src = await File(path).open();
  final sink = await File(out).open(mode: FileMode.write);
  try {
    final total = await src.length();
    await src.setPosition(44);
    final dataLen = total - 44;
    final outLen = (dataLen ~/ 6) * 2;
    await sink.writeFrom(_header(outLen, 16000));
    final ds = Downsampler3();
    while (true) {
      final chunk = await src.read(48000 * 2); // ~1 s por vuelta
      if (chunk.isEmpty) break;
      await sink.writeFrom(ds.add(chunk));
    }
  } finally {
    await src.close();
    await sink.close();
  }
  return out;
}

Uint8List _header(int dataLen, int rate) {
  final b = ByteData(44);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  return b.buffer.asUint8List();
}
