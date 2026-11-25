import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Copia de seguridad de TODA la app (base de datos, hojas, audios, fotos,
/// stickers y ajustes) en un solo archivo `.appnotas` que se puede guardar
/// en Google Drive, WhatsApp, etc.
///
/// Formato (comprimido con gzip): "APPNOTAS1", luego por cada archivo
/// [largo de la ruta (4 bytes)][ruta][tamaño (8 bytes)][contenido].
/// El archivo especial "__prefs.json" lleva los ajustes.
class BackupService {
  static const _magic = 'APPNOTAS1';
  static const _restoreDir = '_restore_pendiente';
  static const _prefsName = '__prefs.json';

  static Future<Directory> _docs() => getApplicationDocumentsDirectory();

  /// Crea la copia y devuelve la ruta del archivo.
  static Future<String> create(SharedPreferences prefs) async {
    final docs = await _docs();
    final now = DateTime.now();
    final name =
        'AppNotas-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.appnotas';
    final out = File(p.join((await getTemporaryDirectory()).path, name));
    final raw = out.openWrite();
    final sink = gzip.encoder.startChunkedConversion(raw);

    void addBytes(List<int> b) => sink.add(b);
    void addInt(int v, int bytes) {
      final d = ByteData(8)..setInt64(0, v);
      addBytes(d.buffer.asUint8List(8 - bytes));
    }

    addBytes(utf8.encode(_magic));
    Future<void> addFile(String rel, List<int> content) async {
      final path = utf8.encode(rel);
      addInt(path.length, 4);
      addBytes(path);
      addInt(content.length, 8);
      addBytes(content);
    }

    // Ajustes.
    final prefsMap = <String, Object?>{
      for (final k in prefs.getKeys()) k: prefs.get(k),
    };
    await addFile(_prefsName, utf8.encode(jsonEncode(prefsMap)));

    // Archivos de la app.
    for (final e in docs.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: docs.path);
      if (rel.startsWith(_restoreDir) || rel.endsWith('.tmp')) continue;
      await addFile(rel, await e.readAsBytes());
    }
    sink.close();
    await raw.done;
    return out.path;
  }

  /// Prepara la restauración: deja los archivos listos para aplicarlos la
  /// próxima vez que se abra la app (así la base de datos no está en uso) y
  /// restaura los ajustes. Devuelve cuántos archivos trae la copia.
  static Future<int> prepareRestore(String backupPath, SharedPreferences prefs) async {
    final docs = await _docs();
    final target = Directory(p.join(docs.path, _restoreDir));
    if (target.existsSync()) target.deleteSync(recursive: true);
    target.createSync(recursive: true);

    final bytes = gzip.decode(await File(backupPath).readAsBytes());
    final data = Uint8List.fromList(bytes);
    final view = ByteData.sublistView(data);
    var i = 0;
    final magic = utf8.decode(data.sublist(0, _magic.length), allowMalformed: true);
    if (magic != _magic) {
      target.deleteSync(recursive: true);
      throw const FormatException('Ese archivo no es una copia de Kumo.');
    }
    i = _magic.length;
    var count = 0;
    while (i < data.length) {
      final len = view.getUint32(i);
      i += 4;
      final rel = utf8.decode(data.sublist(i, i + len));
      i += len;
      final size = view.getInt64(i);
      i += 8;
      final content = data.sublist(i, i + size);
      i += size;
      if (rel == _prefsName) {
        final map = (jsonDecode(utf8.decode(content)) as Map).cast<String, Object?>();
        await prefs.clear();
        for (final MapEntry(:key, :value) in map.entries) {
          switch (value) {
            case final bool v:
              await prefs.setBool(key, v);
            case final int v:
              await prefs.setInt(key, v);
            case final double v:
              await prefs.setDouble(key, v);
            case final String v:
              await prefs.setString(key, v);
            case final List v:
              await prefs.setStringList(key, v.cast<String>());
          }
        }
        continue;
      }
      // Evitar rutas que salgan de la carpeta.
      final dest = p.normalize(p.join(target.path, rel));
      if (!p.isWithin(target.path, dest)) continue;
      File(dest)
        ..createSync(recursive: true)
        ..writeAsBytesSync(content);
      count++;
    }
    return count;
  }

  /// Se llama al abrir la app, ANTES de abrir la base de datos.
  static Future<void> applyPendingRestore() async {
    final docs = await _docs();
    final pending = Directory(p.join(docs.path, _restoreDir));
    if (!pending.existsSync()) return;
    for (final e in docs.listSync(followLinks: false)) {
      if (p.basename(e.path) == _restoreDir) continue;
      e.deleteSync(recursive: true);
    }
    for (final e in pending.listSync(followLinks: false)) {
      e.renameSync(p.join(docs.path, p.basename(e.path)));
    }
    pending.deleteSync(recursive: true);
  }
}
