import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
  static const _preparingDir = '_restore_preparando';
  static const _oldDir = '_antes_de_restaurar';
  static const _readyMark = '.copia_lista';
  static const _pendingPrefs = '.ajustes_de_la_copia.json';
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
    await discardTemp(tmp);
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
    await discardTemp(tmp);
    await prefs.setInt(lastAutoKey, t.millisecondsSinceEpoch);
    final all = await autoCopies();
    for (final old in all.skip(_keep)) {
      await old.delete();
    }
    return dest.path;
  }

  /// Borra una copia temporal hecha con [create] (y su carpeta).
  static Future<void> discardTemp(String path) async {
    try {
      await File(path).parent.delete(recursive: true);
    } catch (_) {}
  }

  /// Saca una foto completa y al día de la base de datos abierta en el
  /// archivo indicado (la pone la app al abrir; ver app.dart). Copiar el
  /// archivo .sqlite mientras está abierto puede dejar afuera los últimos
  /// cambios, que todavía están en el .sqlite-wal.
  static Future<void> Function(String dest)? databaseSnapshot;

  static const _dbFiles = {'app_notas.sqlite', 'app_notas.sqlite-wal', 'app_notas.sqlite-shm'};

  /// Crea la copia y devuelve la ruta del archivo.
  static Future<String> create(SharedPreferences prefs) async {
    final docs = await _docs();
    if (await hasPendingRestore(docs: docs)) throw const RestorePendingException();
    final now = DateTime.now();
    final name =
        'Kumo-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.appnotas';
    // Una carpeta temporal propia por copia: si se hacen dos a la vez (la
    // semanal y la de Drive), no escriben en el mismo archivo.
    final tmpDir = await (await getTemporaryDirectory()).createTemp('kumo-copia-');
    final out = File(p.join(tmpDir.path, name));
    // La base de datos, de una sola vez y sin cambios a medias.
    File? dbCopy;
    final snapshot = databaseSnapshot;
    if (snapshot != null) {
      final f = File(p.join(tmpDir.path, 'base.sqlite'));
      try {
        await snapshot(f.path);
        if (f.existsSync() && f.lengthSync() > 0) dbCopy = f;
      } catch (_) {
        // Si no se pudo, se copia el archivo como antes.
      }
    }
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
    final prefsMap = <String, Object?>{for (final k in prefs.getKeys()) k: prefs.get(k)};
    await addFile(_prefsName, utf8.encode(jsonEncode(prefsMap)));
    // De qué carpeta vienen (para corregir las rutas en otro aparato).
    await addFile(_rootName, utf8.encode(docs.path));

    // Archivos de la app.
    for (final e in docs.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: docs.path);
      if (rel.startsWith(_restoreDir) ||
          rel.startsWith(_preparingDir) ||
          rel.startsWith(_oldDir) ||
          rel.endsWith('.tmp') ||
          rel.startsWith('.ruta_') ||
          (dbCopy != null && _dbFiles.contains(rel))) {
        continue;
      }
      await addFile(rel, await e.readAsBytes());
    }
    if (dbCopy != null) {
      await addFile('app_notas.sqlite', await dbCopy.readAsBytes());
      await dbCopy.delete();
    }
    sink.close();
    await raw.done;
    return out.path;
  }

  /// Hay una copia lista para aplicar al volver a abrir la app. Mientras
  /// tanto no se hacen copias ni se sube nada: lo que hay en la carpeta es
  /// lo de antes, y subirlo pisaría en Drive lo que se acaba de traer.
  static Future<bool> hasPendingRestore({Directory? docs}) async {
    final d = docs ?? await _docs();
    return Directory(p.join(d.path, _restoreDir)).existsSync();
  }

  /// Descarta una restauración preparada que todavía no se aplicó.
  static Future<void> discardPendingRestore({Directory? docs}) async {
    final d = docs ?? await _docs();
    for (final name in [_restoreDir, _preparingDir]) {
      final dir = Directory(p.join(d.path, name));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  }

  /// Prepara la restauración: deja los archivos listos para aplicarlos la
  /// próxima vez que se abra la app (así la base de datos no está en uso).
  /// Devuelve cuántos archivos trae la copia.
  ///
  /// Todo se escribe primero en una carpeta aparte y solo al final, si la
  /// copia se leyó completa y sin errores, pasa a ser "la pendiente". Así una
  /// copia cortada (se cayó el internet) o dañada nunca borra lo que hay.
  /// Los ajustes también se aplican recién al abrir de nuevo.
  /// La copia se lee por partes, sin cargarla entera en la memoria.
  static Future<int> prepareRestore(String backupPath, {Directory? docs}) async {
    final root = docs ?? await _docs();
    final work = Directory(p.join(root.path, _preparingDir));
    if (work.existsSync()) work.deleteSync(recursive: true);
    work.createSync(recursive: true);
    try {
      final count = await _unpack(File(backupPath), work);
      File(p.join(work.path, _readyMark)).writeAsStringSync(DateTime.now().toIso8601String());
      final pending = Directory(p.join(root.path, _restoreDir));
      if (pending.existsSync()) pending.deleteSync(recursive: true);
      work.renameSync(pending.path);
      return count;
    } catch (_) {
      if (work.existsSync()) work.deleteSync(recursive: true);
      rethrow;
    }
  }

  /// Lee la copia [file] y deja sus archivos en [target]. Falla si la copia
  /// no es de Kumo, está cortada o no trae la base de datos.
  static Future<int> _unpack(File file, Directory target) async {
    final magic = utf8.encode(_magic);
    // Etapas: 0 = encabezado "APPNOTAS1", 1 = largo de la ruta, 2 = ruta,
    // 3 = tamaño, 4 = contenido.
    var stage = 0;
    var need = magic.length;
    var carry = Uint8List(0);
    var rel = '';
    var remaining = 0;
    RandomAccessFile? out;
    BytesBuilder? small; // ajustes y ruta de origen (archivos chicos)
    var skip = false;
    var count = 0;
    var hasDb = false;
    var hasPrefs = false;

    Future<void> openEntry() async {
      skip = false;
      small = null;
      out = null;
      if (rel == _rootName || rel == _prefsName) {
        small = BytesBuilder(copy: false);
        return;
      }
      // Evitar rutas que salgan de la carpeta.
      final dest = p.normalize(p.join(target.path, rel));
      if (!p.isWithin(target.path, dest) || p.basename(dest) == _readyMark || p.basename(dest) == _pendingPrefs) {
        skip = true;
        return;
      }
      await File(dest).parent.create(recursive: true);
      out = await File(dest).open(mode: FileMode.write);
    }

    Future<void> closeEntry() async {
      if (small != null) {
        final bytes = small!.takeBytes();
        if (rel == _rootName) {
          File(p.join(target.path, '.ruta_anterior')).writeAsBytesSync(bytes);
        } else {
          // Se aplican al abrir de nuevo (ver applyPendingRestore).
          jsonDecode(utf8.decode(bytes)) as Map; // que sea un JSON válido
          File(p.join(target.path, _pendingPrefs)).writeAsBytesSync(bytes);
          hasPrefs = true;
        }
      } else if (out != null) {
        await out!.close();
        count++;
        if (rel == 'app_notas.sqlite') hasDb = true;
      }
      small = null;
      out = null;
    }

    try {
      await for (final chunk in file.openRead().transform(gzip.decoder)) {
        final data =
            carry.isEmpty
                ? (chunk is Uint8List ? chunk : Uint8List.fromList(chunk))
                : (BytesBuilder(copy: false)
                      ..add(carry)
                      ..add(chunk))
                    .takeBytes();
        carry = Uint8List(0);
        var off = 0;
        while (off < data.length) {
          if (stage == 4) {
            final n = math.min(remaining, data.length - off);
            final part = Uint8List.sublistView(data, off, off + n);
            if (small != null) {
              small!.add(Uint8List.fromList(part));
            } else if (!skip) {
              await out!.writeFrom(part);
            }
            off += n;
            remaining -= n;
            if (remaining == 0) {
              await closeEntry();
              stage = 1;
              need = 4;
            }
            continue;
          }
          if (data.length - off < need) {
            carry = Uint8List.fromList(Uint8List.sublistView(data, off));
            break;
          }
          final part = Uint8List.sublistView(data, off, off + need);
          off += need;
          final view = ByteData.sublistView(part);
          switch (stage) {
            case 0:
              for (var k = 0; k < magic.length; k++) {
                if (part[k] != magic[k]) throw const FormatException('Ese archivo no es una copia de Kumo.');
              }
              stage = 1;
              need = 4;
            case 1:
              stage = 2;
              need = view.getUint32(0);
              if (need > 4096) throw const FormatException('La copia está dañada.');
            case 2:
              rel = utf8.decode(part);
              stage = 3;
              need = 8;
            case 3:
              remaining = view.getInt64(0);
              if (remaining < 0) throw const FormatException('La copia está dañada.');
              await openEntry();
              if (remaining == 0) {
                await closeEntry();
                stage = 1;
                need = 4;
              } else {
                stage = 4;
              }
          }
        }
      }
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('La copia está cortada o dañada ($e).');
    } finally {
      await out?.close();
    }
    // Tiene que terminar justo al final de un archivo.
    if (stage == 0) throw const FormatException('Ese archivo no es una copia de Kumo.');
    if (stage != 1 || carry.isNotEmpty) {
      throw const FormatException('La copia está cortada (¿se cortó el internet?). No se cambió nada.');
    }
    if (!hasDb || !hasPrefs) {
      throw const FormatException('La copia está incompleta: no trae tus notas. No se cambió nada.');
    }
    return count;
  }

  /// Se llama al abrir la app, ANTES de abrir la base de datos.
  ///
  /// Primero se aparta lo que hay ahora, después se pone lo de la copia y
  /// recién al final se borra lo apartado. Si algo falla en el medio, se
  /// vuelve a poner lo de antes: nunca queda la carpeta vacía.
  static Future<void> applyPendingRestore({Directory? docs, SharedPreferences? prefs}) async {
    final root = docs ?? await _docs();
    final pending = Directory(p.join(root.path, _restoreDir));
    final old = Directory(p.join(root.path, _oldDir));
    final work = Directory(p.join(root.path, _preparingDir));
    bool special(FileSystemEntity e) => {_restoreDir, _oldDir, _preparingDir}.contains(p.basename(e.path));

    // Una preparación que no terminó (se cerró la app a la mitad): no sirve.
    if (work.existsSync()) work.deleteSync(recursive: true);

    void rollback() {
      if (!old.existsSync()) return;
      for (final e in root.listSync(followLinks: false)) {
        if (!special(e)) e.deleteSync(recursive: true);
      }
      for (final e in old.listSync(followLinks: false)) {
        e.renameSync(p.join(root.path, p.basename(e.path)));
      }
      old.deleteSync(recursive: true);
    }

    if (!pending.existsSync()) {
      // La vez anterior se terminó de poner la copia: lo apartado sobra.
      if (old.existsSync()) old.deleteSync(recursive: true);
      return;
    }
    // Sin la marca de "lista" (versiones viejas dejaban la carpeta a medias
    // si la copia fallaba): no se toca nada.
    if (!File(p.join(pending.path, _readyMark)).existsSync()) {
      pending.deleteSync(recursive: true);
      return;
    }
    // Se cerró la app mientras se cambiaban los archivos: volver a empezar
    // desde lo que había.
    rollback();

    try {
      old.createSync();
      for (final e in root.listSync(followLinks: false)) {
        if (!special(e)) e.renameSync(p.join(old.path, p.basename(e.path)));
      }
      final prefsFile = File(p.join(pending.path, _pendingPrefs));
      for (final e in pending.listSync(followLinks: false)) {
        final name = p.basename(e.path);
        if (name == _readyMark || name == _pendingPrefs) continue;
        e.renameSync(p.join(root.path, name));
      }
      if (prefsFile.existsSync()) {
        await _applyPrefs(prefs ?? await SharedPreferences.getInstance(), prefsFile.readAsStringSync());
      }
    } catch (_) {
      // Volver a lo de antes y olvidar esta copia.
      rollback();
      if (pending.existsSync()) pending.deleteSync(recursive: true);
      rethrow;
    }
    pending.deleteSync(recursive: true);
    old.deleteSync(recursive: true);
  }

  /// Pone los ajustes de la copia, pero lo propio de este aparato (cuenta de
  /// Google, sincronización) se queda.
  static Future<void> _applyPrefs(SharedPreferences prefs, String raw) async {
    final map = (jsonDecode(raw) as Map).cast<String, Object?>();
    bool own(String k) => k.startsWith('drive.') || k.startsWith('google.') || k.startsWith('sync.');
    final keep = {
      for (final k in prefs.getKeys())
        if (own(k)) k: prefs.get(k),
    };
    map.removeWhere((k, _) => own(k));
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
  }
}

/// Hay una copia traída esperando a que se vuelva a abrir Kumo.
class RestorePendingException implements Exception {
  const RestorePendingException();
  @override
  String toString() => 'Hay una copia lista para poner: cierra Kumo y vuelve a abrirlo.';
}
