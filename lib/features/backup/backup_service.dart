import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/files/app_dirs.dart';
import '../../core/platform_info.dart';

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
  static const _rootName = '.ruta_origen';

  static Future<Directory> _docs() => appDataDir();

  // ------------------------------------------------- Copia automática

  static const autoKey = 'backup.auto';
  static const lastAutoKey = 'backup.lastAuto';
  static const _keep = 3;

  /// Carpeta de las copias automáticas (en el almacenamiento del teléfono,
  /// Android/data/…/files/Copias). Ojo: se borra si desinstalas la app, por
  /// eso conviene compartir una copia a Drive de vez en cuando.
  static Future<Directory> autoDir() async {
    // En la compu, al lado de la carpeta de datos (no adentro: si no, cada
    // copia incluiría las anteriores y restaurar las borraría).
    final base = isPhone
        ? (await getExternalStorageDirectory() ?? await _docs())
        : await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, isPhone ? 'Copias' : 'kumo-copias'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Copia de seguridad de lo que hay ahora, antes de reemplazarlo con lo de
  /// otro aparato. Queda junto a las copias automáticas.
  static Future<String> safetyCopy(SharedPreferences prefs) async {
    final tmp = await create(prefs);
    final dest = File(p.join((await autoDir()).path, 'Antes-de-sincronizar-${p.basename(tmp)}'));
    await File(tmp).copy(dest.path);
    await File(tmp).delete();
    final all = await autoCopies();
    for (final old in all.where((f) => p.basename(f.path).startsWith('Antes-de-sincronizar')).skip(2)) {
      await old.delete();
    }
    return dest.path;
  }

  /// Copias automáticas, de la más nueva a la más vieja.
  static Future<List<File>> autoCopies() async {
    final d = await autoDir();
    final l = d.listSync().whereType<File>().where((f) => f.path.endsWith('.appnotas')).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return l;
  }

  /// Si pasó una semana desde la última, hace una copia sola (al abrir la
  /// app) y guarda solo las 3 más recientes. Devuelve la ruta o null.
  static Future<String?> autoBackupIfDue(SharedPreferences prefs, {DateTime? now}) async {
    if (!(prefs.getBool(autoKey) ?? true)) return null;
    final t = now ?? DateTime.now();
    final last = prefs.getInt(lastAutoKey);
    if (last != null && t.difference(DateTime.fromMillisecondsSinceEpoch(last)) < const Duration(days: 7)) {
      return null;
    }
    final tmp = await create(prefs);
    final dest = File(p.join((await autoDir()).path, p.basename(tmp)));
    await File(tmp).copy(dest.path);
    await File(tmp).delete();
    await prefs.setInt(lastAutoKey, t.millisecondsSinceEpoch);
    final all = await autoCopies();
    for (final old in all.skip(_keep)) {
      await old.delete();
    }
    return dest.path;
  }

  /// Crea la copia y devuelve la ruta del archivo.
  static Future<String> create(SharedPreferences prefs) async {
    final docs = await _docs();
    final now = DateTime.now();
    final name =
        'Kumo-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.appnotas';
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
    // De qué carpeta vienen (para corregir las rutas en otro aparato).
    await addFile(_rootName, utf8.encode(docs.path));

    // Archivos de la app.
    for (final e in docs.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: docs.path);
      if (rel.startsWith(_restoreDir) || rel.endsWith('.tmp') || rel.startsWith('.ruta_')) continue;
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
      if (rel == _rootName) {
        File(p.join(target.path, '.ruta_anterior')).writeAsStringSync(utf8.decode(content));
        continue;
      }
      if (rel == _prefsName) {
        final map = (jsonDecode(utf8.decode(content)) as Map).cast<String, Object?>();
        // Lo propio de este aparato (cuenta de Google, sincronización) se queda.
        final keep = {
          for (final k in prefs.getKeys())
            if (k.startsWith('drive.') || k.startsWith('google.') || k.startsWith('sync.')) k: prefs.get(k),
        };
        map.removeWhere((k, _) => k.startsWith('drive.') || k.startsWith('google.') || k.startsWith('sync.'));
        map.addAll(keep);
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
