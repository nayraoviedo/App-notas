import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform_info.dart';

/// Carpeta donde Kumo guarda TODO (base de datos, audios, hojas, fotos…).
///
/// En el celular es la carpeta privada de la app. En la compu NO puede ser
/// "Documentos" del usuario (ahí había archivos de la persona, y restaurar
/// una copia borra la carpeta entera): se usa la carpeta de datos de la app
/// (AppData en Windows, ~/.local/share en Linux), en una subcarpeta "kumo".
Future<Directory> appDataDir() async {
  if (isPhone) return getApplicationDocumentsDirectory();
  final d = Directory(p.join((await getApplicationSupportDirectory()).path, 'kumo'));
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

/// Lo que Kumo guarda en su carpeta (para mudarlo sin tocar nada más).
const kumoEntries = [
  'app_notas.sqlite',
  'app_notas.sqlite-wal',
  'app_notas.sqlite-shm',
  'audio',
  'drawings',
  'pages',
  'images',
  'covers',
  'videos',
  'video_frames',
  'stickers',
  'fuentes',
  'plantillas',
];

const _oldRootFile = '.ruta_anterior';

/// Versiones de escritorio anteriores guardaban en "Documentos". Si es así,
/// se mudan SOLO los archivos de Kumo a la carpeta nueva (antes de abrir la
/// base de datos) y se anota la ruta vieja para corregir las rutas.
Future<void> migrateDesktopData() async {
  if (isPhone) return;
  try {
    final docs = await getApplicationDocumentsDirectory();
    final target = await appDataDir();
    final oldDb = File(p.join(docs.path, 'app_notas.sqlite'));
    if (!oldDb.existsSync() || File(p.join(target.path, 'app_notas.sqlite')).existsSync()) return;
    for (final name in kumoEntries) {
      final from = p.join(docs.path, name);
      final to = p.join(target.path, name);
      if (FileSystemEntity.typeSync(from) == FileSystemEntityType.notFound) continue;
      try {
        await (FileSystemEntity.isDirectorySync(from) ? Directory(from) : File(from)).rename(to);
      } catch (_) {
        // Otro disco: copiar y borrar.
        if (FileSystemEntity.isDirectorySync(from)) {
          await _copyDir(Directory(from), Directory(to));
          await Directory(from).delete(recursive: true);
        } else {
          await File(from).copy(to);
          await File(from).delete();
        }
      }
    }
    await markOldRoot(docs.path);
  } catch (_) {}
}

Future<void> _copyDir(Directory from, Directory to) async {
  await to.create(recursive: true);
  for (final e in from.listSync(recursive: true, followLinks: false)) {
    final rel = p.relative(e.path, from: from.path);
    if (e is Directory) {
      await Directory(p.join(to.path, rel)).create(recursive: true);
    } else if (e is File) {
      await File(p.join(to.path, rel)).parent.create(recursive: true);
      await e.copy(p.join(to.path, rel));
    }
  }
}

/// Anota que los archivos venían de [oldRoot] (otra compu, el celular o una
/// carpeta vieja): al abrir, [rebasePaths] corrige las rutas guardadas.
Future<void> markOldRoot(String oldRoot) async {
  final root = await appDataDir();
  if (p.equals(oldRoot, root.path)) return;
  await File(p.join(root.path, _oldRootFile)).writeAsString(oldRoot);
}

/// ¿Hay rutas por corregir?
Future<bool> needsRebase() async => File(p.join((await appDataDir()).path, _oldRootFile)).existsSync();

/// La base de datos y las hojas guardan rutas completas a los archivos.
/// Si los datos vienen de otra carpeta (otro aparato), se cambian por la
/// carpeta de este aparato. Se llama con la base ya abierta.
Future<void> rebasePaths(GeneratedDatabase db, SharedPreferences prefs) async {
  final root = await appDataDir();
  final marker = File(p.join(root.path, _oldRootFile));
  if (!marker.existsSync()) return;
  final oldRoot = (await marker.readAsString()).trim();
  final newRoot = root.path;
  if (oldRoot.isEmpty || oldRoot == newRoot) {
    await marker.delete();
    return;
  }
  final toSlash = !Platform.isWindows;

  // 1) Base de datos: todas las columnas de texto de todas las tablas.
  final tables = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
      .get();
  for (final t in tables) {
    final table = t.read<String>('name');
    final cols = await db.customSelect('PRAGMA table_info("$table")').get();
    for (final c in cols) {
      final type = (c.read<String>('type')).toUpperCase();
      if (!type.contains('TEXT') && type.isNotEmpty) continue;
      final col = c.read<String>('name');
      await db.customStatement(
        'UPDATE "$table" SET "$col" = ? || substr("$col", ?) WHERE substr("$col", 1, ?) = ?',
        [newRoot, oldRoot.length + 1, oldRoot.length, oldRoot],
      );
      if (toSlash) {
        await db.customStatement(
          'UPDATE "$table" SET "$col" = replace("$col", ?, ?) WHERE substr("$col", 1, ?) = ?',
          ['\\', '/', newRoot.length, newRoot],
        );
      }
    }
  }

  // 2) Hojas, plantillas y demás .json: rutas dentro del texto.
  for (final e in root.listSync(recursive: true, followLinks: false)) {
    if (e is! File || !e.path.endsWith('.json')) continue;
    final s = await e.readAsString();
    final fixed = rebaseJsonText(s, oldRoot, newRoot, toSlash: toSlash);
    if (fixed != s) await e.writeAsString(fixed);
  }

  // 3) Ajustes que guardan rutas (portadas, letras propias…).
  for (final k in prefs.getKeys()) {
    final v = prefs.get(k);
    if (v is String && v.contains(oldRoot)) {
      await prefs.setString(k, v.replaceAll(oldRoot, newRoot).let((s) => toSlash ? _slashUnder(s, newRoot) : s));
    } else if (v is String && v.contains(jsonEncode(oldRoot).replaceAll('"', ''))) {
      await prefs.setString(k, rebaseJsonText(v, oldRoot, newRoot, toSlash: toSlash));
    }
  }
  await marker.delete();
}

/// Cambia [oldRoot] por [newRoot] dentro de un texto JSON (donde "\" va
/// escrito "\\").
String rebaseJsonText(String s, String oldRoot, String newRoot, {required bool toSlash}) {
  String esc(String x) => jsonEncode(x).substring(1, jsonEncode(x).length - 1);
  final o = esc(oldRoot), n = esc(newRoot);
  if (!s.contains(o)) return s;
  final replaced = s.replaceAll(o, n);
  if (!toSlash) return replaced;
  // Dentro de esas rutas, "\\" (Windows) pasa a "/".
  return replaced.replaceAllMapped(
    RegExp('${RegExp.escape(n)}[^"]*'),
    (m) => m[0]!.replaceAll(r'\\', '/'),
  );
}

String _slashUnder(String s, String root) =>
    s.replaceAllMapped(RegExp('${RegExp.escape(root)}[^;,]*'), (m) => m[0]!.replaceAll('\\', '/'));

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
