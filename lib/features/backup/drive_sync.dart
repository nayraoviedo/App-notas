import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';
import '../../core/google_auth.dart';

/// Copia de TODA la app en tu Google Drive, en la carpeta privada de la app
/// (no se ve entre tus archivos y solo Kumo puede leerla). Usa el espacio
/// de tu cuenta de Google (15 GB gratis).
class DriveSync {
  DriveSync._();
  static final instance = DriveSync._();

  static const scopes = ['https://www.googleapis.com/auth/drive.appdata'];
  static const _name = 'kumo-respaldo.appnotas';
  static const clientIdKey = 'drive.webClientId';
  static const emailKey = 'drive.email';
  static const lastKey = 'drive.last';
  static const autoKey = 'drive.auto';

  static const defaultClientId = GoogleAuth.defaultWebClientId;

  final _auth = GoogleAuth.instance;
  Future<String> _tok(SharedPreferences prefs, {bool interactive = false}) async {
    try {
      return await _auth.token(prefs, scopes, interactive: interactive);
    } on GoogleAuthException catch (e) {
      throw DriveException(e.message);
    }
  }

  /// Iniciar sesión (ventana de Google en el celular; navegador en la
  /// compu). Devuelve el correo.
  Future<String> connect(SharedPreferences prefs) async {
    try {
      final email = await _auth.signIn(prefs, scopes);
      await _auth.token(prefs, scopes, interactive: true);
      await prefs.setString(emailKey, email);
      return email;
    } on GoogleAuthException catch (e) {
      throw DriveException(e.message);
    }
  }

  Future<void> disconnect(SharedPreferences prefs) async {
    await _auth.signOut(prefs);
    await prefs.remove(emailKey);
  }

  Map<String, String> _h(String token) => {'Authorization': 'Bearer $token'};

  static const shareScopes = ['https://www.googleapis.com/auth/drive.file'];

  /// Sube un archivo a tu Drive (carpeta "Kumo compartidos") y devuelve un
  /// link que cualquiera puede abrir para verlo (no para editarlo).
  Future<String> shareFile(SharedPreferences prefs, Uint8List bytes, String fileName,
      {String mime = 'application/pdf', void Function(String)? onStatus}) async {
    final String token;
    try {
      token = await _auth.token(prefs, shareScopes, interactive: true);
    } on GoogleAuthException catch (e) {
      throw DriveException(e.message);
    }

    onStatus?.call('Subiendo a tu Google Drive…');
    final folder = await _shareFolder(token);
    final boundary = 'kumo${DateTime.now().microsecondsSinceEpoch}';
    final meta = jsonEncode({'name': fileName, 'parents': [folder], 'mimeType': mime});
    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'))
      ..add(utf8.encode('--$boundary\r\nContent-Type: $mime\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));
    final up = await http.post(
      Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink'),
      headers: {..._h(token), 'Content-Type': 'multipart/related; boundary=$boundary'},
      body: body.takeBytes(),
    );
    _check(up);
    final j = jsonDecode(up.body) as Map;
    final id = j['id'] as String;

    onStatus?.call('Creando el link…');
    final perm = await http.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files/$id/permissions'),
      headers: {..._h(token), 'Content-Type': 'application/json'},
      body: jsonEncode({'role': 'reader', 'type': 'anyone'}),
    );
    _check(perm);
    return j['webViewLink'] as String? ?? 'https://drive.google.com/file/d/$id/view';
  }

  /// Carpeta "Kumo compartidos" en tu Drive (se crea la primera vez).
  Future<String> _shareFolder(String token) async {
    const name = 'Kumo compartidos';
    final res = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "name = '$name' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        'fields': 'files(id)',
      }),
      headers: _h(token),
    );
    _check(res);
    final files = (jsonDecode(res.body)['files'] as List?) ?? const [];
    if (files.isNotEmpty) return files.first['id'] as String;
    final made = await http.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id'),
      headers: {..._h(token), 'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'mimeType': 'application/vnd.google-apps.folder'}),
    );
    _check(made);
    return (jsonDecode(made.body) as Map)['id'] as String;
  }

  /// Copias guardadas en Drive (la más nueva primero): (id, fecha, bytes).
  Future<List<(String, DateTime, int)>> list(SharedPreferences prefs) async {
    final token = await _tok(prefs);
    final res = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': "name = '$_name' and trashed = false",
        'fields': 'files(id,modifiedTime,size)',
        'orderBy': 'modifiedTime desc',
      }),
      headers: _h(token),
    );
    _check(res);
    return [
      for (final f in (jsonDecode(res.body)['files'] as List? ?? const []))
        (
          f['id'] as String,
          DateTime.tryParse(f['modifiedTime'] as String? ?? '')?.toLocal() ?? DateTime(2000),
          int.tryParse('${f['size'] ?? 0}') ?? 0,
        ),
    ];
  }

  /// Sube una copia nueva y borra las viejas (deja las 2 más recientes).
  Future<void> upload(SharedPreferences prefs, {void Function(String)? onStatus}) async {
    final token = await _tok(prefs);
    onStatus?.call('Preparando la copia…');
    final path = await BackupService.create(prefs);
    final file = File(path);
    final size = await file.length();
    onStatus?.call('Subiendo a Google Drive (${(size / 1048576).toStringAsFixed(1)} MB)…');

    // Subida "reanudable": primero los datos del archivo, luego el contenido.
    final start = await http.post(
      Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable'),
      headers: {
        ..._h(token),
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': '$size',
      },
      body: jsonEncode({
        'name': _name,
        'parents': ['appDataFolder'],
        // Qué aparato la subió (para avisar en el otro que hay cambios).
        'appProperties': {'device': deviceId(prefs), 'from': _deviceName},
      }),
    );
    _check(start);
    final url = start.headers['location'];
    if (url == null) throw const DriveException('Google Drive no aceptó la subida.');
    final req = http.StreamedRequest('PUT', Uri.parse(url))
      ..headers['Content-Length'] = '$size'
      ..headers['Content-Type'] = 'application/octet-stream'
      ..contentLength = size;
    unawaited(file.openRead().pipe(req.sink));
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 30)));
    _check(res);
    await file.delete().catchError((_) => file);

    // Limpiar copias viejas.
    final all = await list(prefs);
    for (final (id, _, _) in all.skip(3)) {
      await http.delete(Uri.https('www.googleapis.com', '/drive/v3/files/$id'), headers: _h(token));
    }
    await prefs.setInt(lastKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt(syncLastKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Baja la copia más reciente y la deja lista para aplicar al reiniciar.
  Future<int> restoreLatest(SharedPreferences prefs, {void Function(String)? onStatus}) async {
    final token = await _tok(prefs);
    final all = await list(prefs);
    if (all.isEmpty) throw const DriveException('Todavía no hay copias en tu Drive.');
    onStatus?.call('Descargando la copia…');
    final req = http.Request(
        'GET', Uri.https('www.googleapis.com', '/drive/v3/files/${all.first.$1}', {'alt': 'media'}))
      ..headers.addAll(_h(token));
    final res = await req.send().timeout(const Duration(minutes: 30));
    if (res.statusCode != 200) throw DriveException('Google Drive respondió ${res.statusCode}.');
    final out = File('${(await getTemporaryDirectory()).path}/$_name');
    await res.stream.pipe(out.openWrite());
    onStatus?.call('Preparando…');
    // Antes de reemplazar, una copia de lo que hay aquí (por si acaso).
    try {
      await BackupService.safetyCopy(prefs);
    } catch (_) {}
    final n = await BackupService.prepareRestore(out.path, prefs);
    await prefs.setInt(syncLastKey, all.first.$2.millisecondsSinceEpoch);
    return n;
  }

  // ------------------------------------------------- Celular ⇄ compu

  static const deviceKey = 'sync.device';
  static const syncLastKey = 'sync.last';

  static String get _deviceName => Platform.isAndroid
      ? 'celular'
      : Platform.isIOS
          ? 'iPhone'
          : Platform.isWindows
              ? 'compu (Windows)'
              : Platform.isMacOS
                  ? 'Mac'
                  : 'compu (Linux)';

  /// Identificador de este aparato (al azar, se crea una vez).
  String deviceId(SharedPreferences prefs) {
    var id = prefs.getString(deviceKey);
    if (id == null) {
      id = '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
      prefs.setString(deviceKey, id);
    }
    return id;
  }

  /// La copia más nueva de Drive si la subió OTRO aparato después de la
  /// última vez que este sincronizó: (fecha, desde qué aparato). Si no, null.
  Future<(DateTime, String)?> newerFromOtherDevice(SharedPreferences prefs) async {
    if (prefs.getString(emailKey) == null) return null;
    final token = await _tok(prefs);
    final res = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': "name = '$_name' and trashed = false",
        'fields': 'files(id,modifiedTime,appProperties)',
        'orderBy': 'modifiedTime desc',
        'pageSize': '1',
      }),
      headers: _h(token),
    );
    _check(res);
    final files = (jsonDecode(res.body)['files'] as List?) ?? const [];
    if (files.isEmpty) return null;
    final f = files.first as Map;
    final props = (f['appProperties'] as Map?) ?? const {};
    if (props['device'] == deviceId(prefs)) return null;
    final when = DateTime.tryParse(f['modifiedTime'] as String? ?? '')?.toLocal();
    if (when == null) return null;
    final last = prefs.getInt(syncLastKey) ?? 0;
    if (when.millisecondsSinceEpoch <= last + 60000) return null;
    return (when, (props['from'] as String?) ?? 'otro aparato');
  }

  /// Sube lo de aquí si pasó [every] desde la última vez, salvo que en Drive
  /// haya algo más nuevo de otro aparato (eso hay que traerlo primero).
  /// Devuelve true si subió.
  Future<bool> syncUpIfDue(SharedPreferences prefs, {Duration every = const Duration(minutes: 30)}) async {
    if (prefs.getString(emailKey) == null || !(prefs.getBool(autoKey) ?? true)) return false;
    final last = prefs.getInt(lastKey);
    if (last != null && DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) < every) {
      return false;
    }
    if (await newerFromOtherDevice(prefs) != null) return false;
    await upload(prefs);
    return true;
  }

  /// Copia diaria automática (al abrir la app), si está conectada.
  Future<void> autoUploadIfDue(SharedPreferences prefs) async {
    if (prefs.getString(emailKey) == null || !(prefs.getBool(autoKey) ?? true)) return;
    final last = prefs.getInt(lastKey);
    if (last != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) < const Duration(hours: 24)) {
      return;
    }
    await upload(prefs);
  }

  void _check(http.Response r) {
    if (r.statusCode == 401) throw const DriveException('Se venció el permiso de Google: vuelve a conectar.');
    if (r.statusCode == 403 && r.body.contains('storageQuota')) {
      throw const DriveException('Tu Google Drive está lleno.');
    }
    if (r.statusCode == 403 && r.body.contains('accessNotConfigured')) {
      throw const DriveException('Falta activar "Google Drive API" en tu proyecto de Google Cloud.');
    }
    if (r.statusCode >= 300) throw DriveException('Google Drive respondió ${r.statusCode}.');
  }
}

class DriveException implements Exception {
  const DriveException(this.message);
  final String message;
  @override
  String toString() => message;
}
