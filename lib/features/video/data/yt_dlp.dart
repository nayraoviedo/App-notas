import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// En la compu no hay reproductor de YouTube incrustado: se usa yt-dlp
/// (programa libre) para obtener el enlace directo del video y se reproduce
/// con el reproductor propio de Kumo. La primera vez Kumo lo baja solo
/// (~30 MB) a su carpeta; no hay que instalar nada.
class YtDlp {
  static Future<File> _bin() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'kumo-tools'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp'));
  }

  static String get _asset => Platform.isWindows
      ? 'yt-dlp.exe'
      : Platform.isMacOS
          ? 'yt-dlp_macos'
          : 'yt-dlp_linux';

  /// Baja (o actualiza, si tiene más de 3 semanas) el programa.
  static Future<File> _ensure(void Function(String)? onStatus) async {
    final f = await _bin();
    final old = f.existsSync() && DateTime.now().difference(f.lastModifiedSync()).inDays > 21;
    if (f.existsSync() && !old) return f;
    onStatus?.call('Preparando el reproductor de YouTube (solo la primera vez)…');
    final res = await http.get(Uri.parse('https://github.com/yt-dlp/yt-dlp/releases/latest/download/$_asset'));
    if (res.statusCode != 200) {
      if (f.existsSync()) return f; // seguir con el que había
      throw Exception('No se pudo bajar el ayudante de YouTube. ¿Hay internet?');
    }
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(res.bodyBytes, flush: true);
    if (f.existsSync()) await f.delete();
    await tmp.rename(f.path);
    if (!Platform.isWindows) await Process.run('chmod', ['+x', f.path]);
    return f;
  }

  /// Enlace directo (video con audio, hasta 720p) de un video de YouTube,
  /// junto con los encabezados que YouTube pide para entregarlo (sin ellos
  /// a veces responde "prohibido" y el video se queda en negro).
  static Future<({String url, Map<String, String> headers})> directUrl(String url,
      {void Function(String)? onStatus}) async {
    final bin = await _ensure(onStatus);
    onStatus?.call('Cargando el video de YouTube…');
    final r = await Process.run(bin.path, [
      '--no-playlist',
      '--no-warnings',
      '-f',
      'best[acodec!=none][vcodec!=none][height<=720]/18/best',
      '-j',
      url,
    ]).timeout(const Duration(seconds: 90));
    Map<String, dynamic>? info;
    if (r.exitCode == 0) {
      for (final line in '${r.stdout}'.split('\n')) {
        if (!line.trimLeft().startsWith('{')) continue;
        try {
          info = jsonDecode(line) as Map<String, dynamic>;
          break;
        } catch (_) {}
      }
    }
    final direct = info?['url'];
    if (info == null || direct is! String || !direct.startsWith('http')) {
      final err = '${r.stderr}';
      if (err.contains('Private video') || err.contains('Sign in')) {
        throw Exception('Ese video es privado o pide iniciar sesión en YouTube.');
      }
      throw Exception('YouTube no dejó abrir este video. Prueba de nuevo en un rato.');
    }
    final raw = info['http_headers'];
    final headers = <String, String>{
      if (raw is Map)
        for (final e in raw.entries)
          if (e.value != null) '${e.key}': '${e.value}',
    };
    return (url: direct, headers: headers);
  }
}
