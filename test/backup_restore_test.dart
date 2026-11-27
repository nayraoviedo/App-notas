import 'dart:io';

import 'package:app_notas/features/backup/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _FakePaths(this.docs, this.tmp);
  final String docs, tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
  @override
  Future<String?> getTemporaryPath() async => tmp;
  @override
  Future<String?> getApplicationSupportPath() async => tmp;
  @override
  Future<String?> getExternalStoragePath() async => tmp;
}

void main() {
  late Directory docs;
  late SharedPreferences prefs;

  setUp(() async {
    final base = await Directory.systemTemp.createTemp('kumo_backup');
    docs = Directory('${base.path}/docs')..createSync();
    final tmp = Directory('${base.path}/tmp')..createSync();
    PathProviderPlatform.instance = _FakePaths(docs.path, tmp.path);
    SharedPreferences.setMockInitialValues({'nombre': 'Nayra'});
    prefs = await SharedPreferences.getInstance();
    File('${docs.path}/app_notas.sqlite').writeAsStringSync('base');
    File('${docs.path}/audio/clase.wav')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(300000, 7));
  });

  test('una copia cortada no se aplica y no borra nada', () async {
    final copy = await BackupService.create(prefs);
    final bytes = File(copy).readAsBytesSync();
    final cut = File('$copy.cortada')..writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));

    await expectLater(BackupService.prepareRestore(cut.path, prefs), throwsFormatException);
    // Los ajustes no cambiaron y no quedó nada pendiente.
    expect(prefs.getString('nombre'), 'Nayra');
    await BackupService.applyPendingRestore();
    expect(File('${docs.path}/app_notas.sqlite').readAsStringSync(), 'base');
    expect(File('${docs.path}/audio/clase.wav').lengthSync(), 300000);
  });

  test('una copia completa se aplica al reabrir', () async {
    final copy = await BackupService.create(prefs);
    File('${docs.path}/app_notas.sqlite').writeAsStringSync('cambiada');
    File('${docs.path}/nueva.txt').writeAsStringSync('x');
    await prefs.setString('nombre', 'Otra');

    final n = await BackupService.prepareRestore(copy, prefs);
    expect(n, greaterThanOrEqualTo(2));
    expect(prefs.getString('nombre'), 'Nayra');
    await BackupService.applyPendingRestore();
    expect(File('${docs.path}/app_notas.sqlite').readAsStringSync(), 'base');
    expect(File('${docs.path}/audio/clase.wav').lengthSync(), 300000);
    expect(File('${docs.path}/nueva.txt').existsSync(), isFalse);
  });

  test('una restauración sin marcar como lista se descarta', () async {
    Directory('${docs.path}/_restore_pendiente/audio').createSync(recursive: true);
    File('${docs.path}/_restore_pendiente/app_notas.sqlite').writeAsStringSync('a medias');
    await BackupService.applyPendingRestore();
    expect(File('${docs.path}/app_notas.sqlite').readAsStringSync(), 'base');
    expect(Directory('${docs.path}/_restore_pendiente').existsSync(), isFalse);
  });
}
