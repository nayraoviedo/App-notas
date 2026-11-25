import 'dart:io';
import 'dart:typed_data';

/// Escribe PCM16 mono a un archivo WAV mientras se graba.
///
/// La cabecera se actualiza cada ~10 s, así que si la app se cierra de golpe
/// el audio grabado hasta ese punto sigue siendo reproducible.
class WavWriter {
  WavWriter(this.path, {this.sampleRate = 16000, this.channels = 1});

  final String path;
  final int sampleRate;
  final int channels;
  static const _bitsPerSample = 16;

  RandomAccessFile? _file;
  int _dataBytes = 0;
  int _bytesSinceHeader = 0;

  int get bytesPerSecond => sampleRate * channels * _bitsPerSample ~/ 8;
  int get durationMs => _dataBytes * 1000 ~/ bytesPerSecond;

  Future<void> open() async {
    _file = await File(path).open(mode: FileMode.write);
    _file!.writeFromSync(_header(0));
  }

  void add(Uint8List pcm) {
    final f = _file;
    if (f == null) return;
    f.writeFromSync(pcm);
    _dataBytes += pcm.length;
    _bytesSinceHeader += pcm.length;
    if (_bytesSinceHeader >= bytesPerSecond * 10) {
      _patchHeader();
      _bytesSinceHeader = 0;
    }
  }

  void _patchHeader() {
    final f = _file!;
    final pos = f.positionSync();
    f
      ..setPositionSync(0)
      ..writeFromSync(_header(_dataBytes))
      ..setPositionSync(pos)
      ..flushSync();
  }

  Future<void> close() async {
    if (_file == null) return;
    _patchHeader();
    await _file!.close();
    _file = null;
  }

  Uint8List _header(int dataLength) {
    final byteRate = bytesPerSecond;
    final blockAlign = channels * _bitsPerSample ~/ 8;
    final b = ByteData(44);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    b.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    b.setUint32(16, 16, Endian.little); // tamaño del bloque fmt
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, channels, Endian.little);
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, byteRate, Endian.little);
    b.setUint16(32, blockAlign, Endian.little);
    b.setUint16(34, _bitsPerSample, Endian.little);
    ascii(36, 'data');
    b.setUint32(40, dataLength, Endian.little);
    return b.buffer.asUint8List();
  }
}
