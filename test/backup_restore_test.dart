import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_notas/features/backup/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Arma una copia con el mismo formato que [BackupService.create].
Uint8List makeBackup(Map<String, List<int>> files, {Map<String, Object?>? prefs}) {
  final b = BytesBuilder();
  void addInt(int v, int bytes) => b.add((ByteData(8)..setInt64(0, v)).buffer.asUint8List(8 - bytes));
  void addFile(String rel, List<int> content) {
    final path = utf8.encode(rel);
    addInt(path.length, 4);
    b.add(path);
    addInt(content.length, 8);
    b.add(content);
  }

  b.add(utf8.encode('APPNOTAS1'));
  addFile('__prefs.json', utf8.encode(jsonEncode(prefs ?? {'flutter.x': 1})));
  addFile('.ruta_origen', utf8.encode('/otro/aparato'));
  files.forEach(addFile);
  return Uint8List.fromList(gzip.encode(b.takeBytes()));
}

void main() {
  late Directory tmp;
  late Directory docs;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kumo-restore-test');
    docs = Directory(p.join(tmp.path, 'kumo'))..createSync();
    File(p.join(docs.path, 'app_notas.sqlite')).writeAsStringSync('base actual');
    File(p.join(docs.path, 'drawings', 'h1.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('hoja actual');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String read(String rel) => File(p.join(docs.path, rel)).readAsStringSync();

  test('una copia completa reemplaza los datos y los ajustes al abrir de nuevo', () async {
    SharedPreferences.setMockInitialValues({'viejo': true, 'drive.email': 'yo', 'sync.device': 'cel'});
    final prefs = await SharedPreferences.getInstance();
    final big = List<int>.generate(300000, (i) => i % 251); // varios pedazos
    final copy = File(p.join(tmp.path, 'c.appnotas'))..writeAsBytesSync(
      makeBackup(
        {
          'app_notas.sqlite': utf8.encode('base nueva'),
          'drawings/h2.json': utf8.encode('hoja nueva'),
          'audio/a.wav': big,
          'vacio.txt': const [],
          '../fuera.txt': utf8.encode('no'),
        },
        prefs: {'nuevo': 'sí', 'drive.email': 'otra', 'sync.device': 'compu'},
      ),
    );

    final n = await BackupService.prepareRestore(copy.path, docs: docs);
    expect(n, 4);
    // Hasta volver a abrir, nada cambia (ni los datos ni los ajustes).
    expect(read('app_notas.sqlite'), 'base actual');
    expect(prefs.getBool('viejo'), true);
    expect(await BackupService.hasPendingRestore(docs: docs), isTrue);

    await BackupService.applyPendingRestore(docs: docs, prefs: prefs);
    expect(read('app_notas.sqlite'), 'base nueva');
    expect(read('drawings/h2.json'), 'hoja nueva');
    expect(File(p.join(docs.path, 'drawings', 'h1.json')).existsSync(), isFalse);
    expect(File(p.join(docs.path, 'audio', 'a.wav')).readAsBytesSync(), big);
    expect(read('.ruta_anterior'), '/otro/aparato');
    expect(File(p.join(tmp.path, 'fuera.txt')).existsSync(), isFalse);
    expect(prefs.getString('nuevo'), 'sí');
    expect(prefs.getBool('viejo'), isNull);
    // Lo propio de este aparato se queda.
    expect(prefs.getString('drive.email'), 'yo');
    expect(prefs.getString('sync.device'), 'cel');
    expect(await BackupService.hasPendingRestore(docs: docs), isFalse);
    expect(docs.listSync().map((e) => p.basename(e.path)), isNot(contains('_antes_de_restaurar')));
  });

  test('una copia cortada no deja nada pendiente ni borra lo que hay', () async {
    SharedPreferences.setMockInitialValues({'viejo': true});
    final prefs = await SharedPreferences.getInstance();
    final full = makeBackup({
      'app_notas.sqlite': utf8.encode('base nueva'),
      'audio/a.wav': List<int>.generate(200000, (i) => (i * 7) % 256),
    });
    for (final cut in [full.length ~/ 3, full.length - 40, 20]) {
      final copy = File(p.join(tmp.path, 'cortada.appnotas'))..writeAsBytesSync(full.sublist(0, cut));
      await expectLater(BackupService.prepareRestore(copy.path, docs: docs), throwsA(anything));
      expect(await BackupService.hasPendingRestore(docs: docs), isFalse);
      await BackupService.applyPendingRestore(docs: docs, prefs: prefs);
      expect(read('app_notas.sqlite'), 'base actual');
      expect(read('drawings/h1.json'), 'hoja actual');
      expect(prefs.getBool('viejo'), true);
    }
  });

  test('una copia sin la base de datos no se acepta', () async {
    final copy = File(p.join(tmp.path, 'c.appnotas'))
      ..writeAsBytesSync(makeBackup({'drawings/h2.json': utf8.encode('x')}));
    await expectLater(BackupService.prepareRestore(copy.path, docs: docs), throwsFormatException);
    expect(await BackupService.hasPendingRestore(docs: docs), isFalse);
  });

  test('un archivo que no es copia de Kumo no cambia nada', () async {
    final copy = File(p.join(tmp.path, 'c.appnotas'))..writeAsBytesSync(gzip.encode(utf8.encode('hola mundo')));
    await expectLater(BackupService.prepareRestore(copy.path, docs: docs), throwsFormatException);
    final notGzip = File(p.join(tmp.path, 'd.appnotas'))..writeAsStringSync('no es gzip');
    await expectLater(BackupService.prepareRestore(notGzip.path, docs: docs), throwsA(anything));
    expect(await BackupService.hasPendingRestore(docs: docs), isFalse);
  });

  test('la carpeta a medias de una versión vieja no borra los datos', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Directory(p.join(docs.path, '_restore_pendiente')).createSync();
    await BackupService.applyPendingRestore(docs: docs, prefs: prefs);
    expect(read('app_notas.sqlite'), 'base actual');
    expect(read('drawings/h1.json'), 'hoja actual');
    expect(await BackupService.hasPendingRestore(docs: docs), isFalse);
  });

  test('si se cerró la app a mitad de poner la copia, se vuelve a empezar bien', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final copy = File(p.join(tmp.path, 'c.appnotas'))
      ..writeAsBytesSync(makeBackup({'app_notas.sqlite': utf8.encode('base nueva')}));
    await BackupService.prepareRestore(copy.path, docs: docs);
    // Simular que se apartó lo de antes y se cortó todo.
    final old = Directory(p.join(docs.path, '_antes_de_restaurar'))..createSync();
    File(p.join(docs.path, 'app_notas.sqlite')).renameSync(p.join(old.path, 'app_notas.sqlite'));
    await BackupService.applyPendingRestore(docs: docs, prefs: prefs);
    expect(read('app_notas.sqlite'), 'base nueva');
    expect(File(p.join(docs.path, 'drawings', 'h1.json')).existsSync(), isFalse);
    expect(old.existsSync(), isFalse);
  });
}
