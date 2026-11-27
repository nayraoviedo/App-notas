import 'dart:async';
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
  static const _readyName = '.restauracion_lista';

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
      // Por partes, sin cargar el archivo entero (audios largos).
      final path = utf8.encode(rel);
      final length = await e.length();
      addInt(path.length, 4);
      addBytes(path);
      addInt(length, 8);
      var written = 0;
      await for (final chunk in e.openRead(0, length)) {
        addBytes(chunk);
        written += chunk.length;
      }
      // Si se achicó mientras se leía, se completa con ceros para que la
      // copia siga siendo legible.
      if (written < length) addBytes(Uint8List(length - written));
    }
    sink.close();
    await raw.done;
    return out.path;
  }

  /// Prepara la restauración: deja los archivos listos para aplicarlos la
  /// próxima vez que se abra la app (así la base de datos no está en uso) y
  /// restaura los ajustes. Devuelve cuántos archivos trae la copia.
  ///
  /// Se lee por partes (sin cargar la copia entera en memoria) y SOLO si
  /// todo salió bien se marca como lista y se cambian los ajustes. Si falla a
  /// la mitad (copia cortada o dañada), no se toca nada de lo que hay.
  static Future<int> prepareRestore(String backupPath, SharedPreferences prefs) async {
    final docs = await _docs();
    final target = Directory(p.join(docs.path, _restoreDir));
    if (target.existsSync()) target.deleteSync(recursive: true);
    target.createSync(recursive: true);

    final reader = _ChunkReader(File(backupPath).openRead().transform(gzip.decoder));
    Map<String, Object?>? prefsMap;
    var count = 0;
    try {
      final magic = await reader.read(_magic.length);
      if (magic == null || utf8.decode(magic, allowMalformed: true) != _magic) {
        throw const FormatException('Ese archivo no es una copia de Kumo.');
      }
      while (true) {
        final lenBytes = await reader.read(4, eofOk: true);
        if (lenBytes == null) break; // fin de la copia, justo entre archivos
        final len = ByteData.sublistView(lenBytes).getUint32(0);
        if (len > 4096) throw const FormatException('La copia está dañada.');
        final rel = utf8.decode((await reader.read(len))!);
        final size = ByteData.sublistView((await reader.read(8))!).getInt64(0);
        if (size < 0) throw const FormatException('La copia está dañada.');

        if (rel == _rootName) {
          File(p.join(target.path, '.ruta_anterior')).writeAsStringSync(utf8.decode((await reader.read(size))!));
          continue;
        }
        if (rel == _prefsName) {
          prefsMap = (jsonDecode(utf8.decode((await reader.read(size))!)) as Map).cast<String, Object?>();
          continue;
        }
        // Evitar rutas que salgan de la carpeta.
        final dest = p.normalize(p.join(target.path, rel));
        if (!p.isWithin(target.path, dest) || p.basename(dest) == _readyName) {
          await reader.skip(size);
          continue;
        }
        final f = File(dest)..createSync(recursive: true);
        final sink = f.openWrite();
        try {
          await reader.copyTo(sink, size);
        } finally {
          await sink.close();
        }
        count++;
      }
      if (count == 0) throw const FormatException('La copia está vacía.');
    } catch (e) {
      // Nada a medias: se borra lo preparado y lo de ahora queda igual.
      try {
        target.deleteSync(recursive: true);
      } catch (_) {}
      if (e is FormatException) rethrow;
      throw FormatException('La copia está incompleta o dañada ($e). No se cambió nada.');
    }

    // Todo bien: recién ahora se cambian los ajustes y se marca como lista.
    if (prefsMap != null) await _restorePrefs(prefsMap, prefs);
    File(p.join(target.path, _readyName)).writeAsStringSync(DateTime.now().toIso8601String(), flush: true);
    return count;
  }

  static Future<void> _restorePrefs(Map<String, Object?> map, SharedPreferences prefs) async {
    // Lo propio de este aparato (cuenta de Google, sincronización) se queda.
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

  /// Se llama al abrir la app, ANTES de abrir la base de datos.
  static Future<void> applyPendingRestore() async {
    final docs = await _docs();
    final pending = Directory(p.join(docs.path, _restoreDir));
    if (!pending.existsSync()) return;
    // Si no está marcada como completa (se cortó al prepararla), NO se
    // aplica: se descarta y los datos de ahora quedan como están.
    final ready = File(p.join(pending.path, _readyName));
    if (!ready.existsSync()) {
      pending.deleteSync(recursive: true);
      return;
    }
    ready.deleteSync();
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


/// Lee un flujo de bytes por partes, pidiendo exactamente lo que hace falta.
class _ChunkReader {
  _ChunkReader(Stream<List<int>> stream) : _it = StreamIterator(stream);
  final StreamIterator<List<int>> _it;
  List<int> _buf = const [];
  int _pos = 0;

  int get _available => _buf.length - _pos;

  Future<bool> _fill() async {
    while (_available == 0) {
      if (!await _it.moveNext()) return false;
      _buf = _it.current;
      _pos = 0;
    }
    return true;
  }

  /// Exactamente [n] bytes. null solo si [eofOk] y el flujo terminó antes
  /// de empezar; si termina a la mitad, es una copia cortada.
  Future<Uint8List?> read(int n, {bool eofOk = false}) async {
    final out = Uint8List(n);
    var got = 0;
    while (got < n) {
      if (!await _fill()) {
        if (got == 0 && eofOk) return null;
        throw const FormatException('La copia está incompleta (se cortó).');
      }
      final take = (n - got) < _available ? (n - got) : _available;
      out.setRange(got, got + take, _buf, _pos);
      _pos += take;
      got += take;
    }
    return out;
  }

  Future<void> copyTo(IOSink sink, int n) async {
    var left = n;
    while (left > 0) {
      if (!await _fill()) throw const FormatException('La copia está incompleta (se cortó).');
      final take = left < _available ? left : _available;
      sink.add(_buf.sublist(_pos, _pos + take));
      _pos += take;
      left -= take;
    }
  }

  Future<void> skip(int n) async {
    var left = n;
    while (left > 0) {
      if (!await _fill()) throw const FormatException('La copia está incompleta (se cortó).');
      final take = left < _available ? left : _available;
      _pos += take;
      left -= take;
    }
  }
}
