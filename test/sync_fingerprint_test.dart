import 'dart:io';

import 'package:app_notas/features/backup/drive_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _FakePaths(this.docs);
  final String docs;
  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
}

void main() {
  test('la huella cambia solo si cambian los datos o el horario/hábitos', () async {
    final docs = await Directory.systemTemp.createTemp('kumo_fp');
    PathProviderPlatform.instance = _FakePaths(docs.path);
    SharedPreferences.setMockInitialValues({'planner.data': '{}'});
    final prefs = await SharedPreferences.getInstance();
    File('${docs.path}/app_notas.sqlite').writeAsStringSync('a');

    final a = await DriveSync.dataFingerprint(prefs);
    expect(await DriveSync.dataFingerprint(prefs), a);
    // Lo propio de la sincronización no cuenta.
    await prefs.setInt('sync.last', 123);
    expect(await DriveSync.dataFingerprint(prefs), a);
    // El horario sí.
    await prefs.setString('planner.data', '{"classes":[]}');
    final b = await DriveSync.dataFingerprint(prefs);
    expect(b, isNot(a));
    // Un archivo nuevo también.
    File('${docs.path}/audio.wav').writeAsStringSync('xx');
    expect(await DriveSync.dataFingerprint(prefs), isNot(b));
  });
}
