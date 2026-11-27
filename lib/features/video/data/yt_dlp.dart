import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Enlace directo de un video de YouTube para el reproductor propio.
typedef YtStream = ({String url, Map<String, String> headers, String? audioUrl});

/// En la compu no hay reproductor de YouTube incrustado: se usa yt-dlp
/// (programa libre) para obtener el enlace directo del video y se reproduce
/// con el reproductor propio de Kumo. La primera vez Kumo lo baja solo a su
/// carpeta; no hay que instalar nada.
///
/// Desde fines de 2025 yt-dlp necesita un motor de JavaScript (Deno) para
/// abrir videos de YouTube; sin él, YouTube no entrega el video. Kumo también
/// lo baja solo (~40 MB, solo la primera vez).
class YtDlp {
  static const _release = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download';
  static const _denoRelease = 'https://github.com/denoland/deno/releases/latest/download';

  static Future<Directory> _dir() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'kumo-tools'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String get _asset => Platform.isWindows
      ? 'yt-dlp.exe'
      : Platform.isMacOS
          ? 'yt-dlp_macos'
          : 'yt-dlp_linux';

  static bool _old(File f, int days) =>
      f.existsSync() && DateTime.now().difference(f.lastModifiedSync()).inDays > days;

  static Future<bool> _download(String url, File dest) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return false;
      final tmp = File('${dest.path}.tmp');
      await tmp.writeAsBytes(res.bodyBytes, flush: true);
      if (dest.existsSync()) await dest.delete();
      await tmp.rename(dest.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _runs(String exe, List<String> args) async {
    try {
      final r = await Process.run(exe, args).timeout(const Duration(seconds: 30));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Cómo llamar a yt-dlp: el programa listo para usar o, si este no abre
  /// en la compu (procesadores antiguos), la versión para Python.
  static List<String>? _cmd;

  static Future<List<String>> _ensure(void Function(String)? onStatus) async {
    final dir = await _dir();
    final bin = File(p.join(dir.path, Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp'));
    if (!bin.existsSync() || _old(bin, 21)) {
      onStatus?.call('Preparando el reproductor de YouTube (solo la primera vez)…');
      if (await _download('$_release/$_asset', bin)) {
        _cmd = null;
        if (!Platform.isWindows) await Process.run('chmod', ['+x', bin.path]);
      } else if (!bin.existsSync()) {
        throw Exception('No se pudo bajar el ayudante de YouTube. ¿Hay internet?');
      }
    }
    if (_cmd != null) return _cmd!;
    if (await _runs(bin.path, ['--version'])) return _cmd = [bin.path];
    if (Platform.isWindows) throw Exception('El ayudante de YouTube no abre en esta compu.');

    // Plan B: la versión para Python (Ubuntu ya trae python3).
    final pyz = File(p.join(dir.path, 'yt-dlp.pyz'));
    if (!pyz.existsSync() || _old(pyz, 21)) {
      onStatus?.call('Preparando el reproductor de YouTube (solo la primera vez)…');
      await _download('$_release/yt-dlp', pyz);
    }
    if (pyz.existsSync() && await _runs('python3', [pyz.path, '--version'])) {
      // Esta versión no trae los scripts para YouTube: se le permite bajarlos.
      return _cmd = ['python3', pyz.path, '--remote-components', 'ejs:github'];
    }
    throw Exception('El ayudante de YouTube no abre en esta compu.');
  }

  /// Deno (motor de JavaScript que yt-dlp necesita para YouTube). Devuelve
  /// la ruta, o null si no se pudo (se intenta igual sin él).
  static Future<String?> _ensureDeno(void Function(String)? onStatus) async {
    if (Platform.isMacOS) return null;
    final dir = await _dir();
    final exe = File(p.join(dir.path, Platform.isWindows ? 'deno.exe' : 'deno'));
    if (!exe.existsSync() || _old(exe, 90)) {
      onStatus?.call('Preparando el reproductor de YouTube (solo la primera vez, puede tardar)…');
      final asset = Platform.isWindows ? 'deno-x86_64-pc-windows-msvc.zip' : 'deno-x86_64-unknown-linux-gnu.zip';
      try {
        final res = await http.get(Uri.parse('$_denoRelease/$asset'));
        if (res.statusCode == 200) {
          final zip = ZipDecoder().decodeBytes(res.bodyBytes);
          final entry = zip.files.firstWhere((f) => f.isFile && p.basename(f.name).startsWith('deno'));
          final tmp = File('${exe.path}.tmp');
          await tmp.writeAsBytes(entry.content as List<int>, flush: true);
          if (exe.existsSync()) await exe.delete();
          await tmp.rename(exe.path);
          if (!Platform.isWindows) await Process.run('chmod', ['+x', exe.path]);
        }
      } catch (_) {}
    }
    if (exe.existsSync() && await _runs(exe.path, ['--version'])) return exe.path;
    return null;
  }

  static bool? _node;
  static Future<bool> _hasNode() async => _node ??= await _runs('node', ['--version']);

  /// Enlace directo (hasta 720p) de un video de YouTube, con los encabezados
  /// que YouTube pide para entregarlo. Si YouTube solo da video y sonido por
  /// separado, [YtStream.audioUrl] trae el sonido.
  static Future<YtStream> directUrl(String url, {void Function(String)? onStatus}) async {
    final cmd = await _ensure(onStatus);
    final deno = await _ensureDeno(onStatus);
    // Node solo si de verdad está instalado (pasarlo sin tenerlo no ayuda).
    final node = deno == null && await _hasNode();
    onStatus?.call('Cargando el video de YouTube…');
    final r = await Process.run(cmd.first, [
      ...cmd.skip(1),
      if (deno != null) ...['--js-runtimes', 'deno:$deno'],
      if (node) ...['--js-runtimes', 'node'],
      '--no-playlist',
      '--no-warnings',
      '-f',
      'b[acodec!=none][vcodec!=none][height<=720]/bv*[height<=720]+ba/b/bv*+ba',
      '-j',
      url,
    ]).timeout(const Duration(seconds: 120));

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

    String? video, audio;
    Map? rawHeaders;
    if (info != null) {
      final parts = info['requested_formats'];
      if (parts is List && parts.isNotEmpty) {
        for (final f in parts.whereType<Map>()) {
          final u = f['url'];
          if (u is! String) continue;
          if (f['vcodec'] != 'none' && video == null) {
            video = u;
            rawHeaders = f['http_headers'] as Map?;
          } else if (f['acodec'] != 'none' && audio == null) {
            audio = u;
          }
        }
      }
      if (video == null && info['url'] is String) {
        video = info['url'] as String;
        audio = null;
      }
      rawHeaders ??= info['http_headers'] as Map?;
    }

    if (video == null || !video.startsWith('http')) {
      final err = '${r.stderr}';
      // Para poder revisar qué pasó.
      try {
        await File(p.join((await _dir()).path, 'yt-dlp-error.txt')).writeAsString(err);
      } catch (_) {}
      if (err.contains('Private video') || err.contains('Sign in')) {
        throw Exception('Ese video es privado o pide iniciar sesión en YouTube.');
      }
      if (deno == null && !node) {
        throw Exception('No se pudo preparar el motor que YouTube necesita '
            '(Deno). Revisa el internet y vuelve a intentar; si sigue, '
            'instala Node.js en la compu.');
      }
      final line = err.split('\n').lastWhere((l) => l.startsWith('ERROR'), orElse: () => '').trim();
      final detail = line.length > 220 ? '${line.substring(0, 220)}…' : line;
      throw Exception('YouTube no dejó abrir este video.${detail.isEmpty ? '' : '\n$detail'}');
    }
    final headers = <String, String>{
      if (rawHeaders != null)
        for (final e in rawHeaders.entries)
          if (e.value != null) '${e.key}': '${e.value}',
    };
    return (url: video, headers: headers, audioUrl: audio);
  }
}
