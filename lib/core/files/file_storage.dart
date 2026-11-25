import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Guarda los archivos de la app (audios, fotos, videos, capturas).
/// La base de datos solo guarda las rutas.
class FileStorage {
  static const _uuid = Uuid();
  Directory? _root;

  Future<Directory> _dir(String name) async {
    _root ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(_root!.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> newAudioPath() async =>
      p.join((await _dir('audio')).path, '${_uuid.v4()}.wav');

  Future<String> newDrawingPath() async =>
      p.join((await _dir('drawings')).path, '${_uuid.v4()}.json');

  /// Copia un archivo externo (foto de la cámara, video de la galería)
  /// a la carpeta de la app para que no se pierda si el sistema limpia la caché.
  Future<String> importFile(String sourcePath, {required String folder}) async {
    final ext = p.extension(sourcePath);
    final target = p.join((await _dir(folder)).path, '${_uuid.v4()}$ext');
    await File(sourcePath).copy(target);
    return target;
  }

  Future<String> saveBytes(Uint8List bytes,
      {required String folder, String ext = '.png'}) async {
    final target = p.join((await _dir(folder)).path, '${_uuid.v4()}$ext');
    await File(target).writeAsBytes(bytes, flush: true);
    return target;
  }

  /// Archivos de una carpeta de la app, del más nuevo al más viejo.
  Future<List<String>> listFolder(String folder) async {
    final files = (await _dir(folder)).listSync().whereType<File>().toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return [for (final f in files) f.path];
  }

  Future<void> deleteIfExists(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
