import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/files/file_storage.dart';
import '../../../core/platform_info.dart';
import '../../backup/drive_sync.dart';

/// Archivos que se pueden ver junto a las notas.
const docExtensions = [
  'pdf', 'ppt', 'pptx', 'pps', 'ppsx', 'odp', 'key',
  'doc', 'docx', 'odt', 'rtf', 'xls', 'xlsx', 'ods',
  'png', 'jpg', 'jpeg', 'webp',
];
const imageExtensions = ['.png', '.jpg', '.jpeg', '.webp'];

/// Mensaje claro para la persona (se muestra tal cual).
class DocException implements Exception {
  const DocException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Tipo de archivo de Google al que se convierte cada formato de Office.
String _googleMimeFor(String ext) => switch (ext) {
      '.doc' || '.docx' || '.odt' || '.rtf' => 'application/vnd.google-apps.document',
      '.xls' || '.xlsx' || '.ods' => 'application/vnd.google-apps.spreadsheet',
      _ => 'application/vnd.google-apps.presentation',
    };

/// Deja el documento listo para verlo: un PDF o una imagen guardada en la
/// carpeta de la app (así se puede volver a abrir y viaja en las copias).
class DocSource {
  DocSource(this._storage, this._prefs);
  final FileStorage _storage;
  final SharedPreferences _prefs;

  Future<String?> pickFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: docExtensions);
    return r?.files.single.path;
  }

  /// Archivo del celular o la compu → ruta dentro de Kumo (PDF o imagen).
  Future<String> fromFile(String path, {void Function(String)? onStatus}) async {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.pdf' || imageExtensions.contains(ext)) {
      return _storage.importFile(path, folder: 'documents');
    }
    return _convert(await File(path).readAsBytes(), p.basename(path), onStatus: onStatus);
  }

  /// Enlace de Google Slides / Docs / Drive o de un PDF en internet.
  Future<String> fromUrl(String url, {void Function(String)? onStatus}) async {
    final u = Uri.tryParse(url.trim());
    if (u == null || !u.hasScheme) throw const DocException('Ese enlace no parece correcto (debe empezar con https://).');
    final download = googleExportUrl(u) ?? u;
    onStatus?.call('Bajando el documento…');
    final http.Response res;
    try {
      res = await http.get(download).timeout(const Duration(minutes: 2));
    } catch (_) {
      throw const DocException('No se pudo bajar. Revisa tu internet.');
    }
    final bytes = res.bodyBytes;
    if (res.statusCode >= 400 || _looksLikeHtml(bytes)) {
      throw DocException(u.host.contains('google')
          ? 'Google no dejó bajarlo. En Google Slides toca Compartir → "Cualquier persona con el enlace", '
              'o descárgalo como PDF y ábrelo con "Archivo".'
          : 'Ese enlace no lleva directo a un PDF. Descárgalo y ábrelo con "Archivo".');
    }
    final name = _nameFrom(u, res);
    if (_isPdf(bytes)) return _storage.saveBytes(bytes, folder: 'documents', ext: '.pdf');
    final ext = p.extension(name).toLowerCase();
    if (imageExtensions.contains(ext)) return _storage.saveBytes(bytes, folder: 'documents', ext: ext);
    return _convert(bytes, name.contains('.') ? name : '$name.pptx', onStatus: onStatus);
  }

  /// PPTX, DOCX… → PDF. En la compu con LibreOffice (o PowerPoint en
  /// Windows); si no hay, o en el celular, con tu cuenta de Google.
  Future<String> _convert(Uint8List bytes, String name, {void Function(String)? onStatus}) async {
    final ext = p.extension(name).toLowerCase();
    if (isDesktop) {
      onStatus?.call('Convirtiendo a PDF…');
      final pdf = await _convertOnComputer(bytes, name);
      if (pdf != null) return _storage.saveBytes(pdf, folder: 'documents', ext: '.pdf');
    }
    try {
      final pdf = await DriveSync.instance
          .convertToPdf(_prefs, bytes, name, googleMime: _googleMimeFor(ext), onStatus: onStatus);
      if (!_isPdf(pdf)) throw const DriveException('Google no pudo convertirlo.');
      return await _storage.saveBytes(pdf, folder: 'documents', ext: '.pdf');
    } on DriveException catch (e) {
      throw DocException(isDesktop
          ? 'No se pudo convertir: ${e.message}\nOtra forma: instala LibreOffice '
              '(en Linux: sudo apt install libreoffice-impress) o guarda la presentación como PDF.'
          : 'No se pudo convertir con Google: ${e.message}\n'
              'Otra forma: en PowerPoint o Google Slides elige "Guardar como PDF" y ábrelo aquí.');
    }
  }

  Future<Uint8List?> _convertOnComputer(Uint8List bytes, String name) async {
    final tmp = await Directory((await getTemporaryDirectory()).path).createTemp('kumo-doc');
    try {
      final input = File(p.join(tmp.path, 'documento${p.extension(name).toLowerCase()}'));
      await input.writeAsBytes(bytes, flush: true);
      final out = File(p.join(tmp.path, 'documento.pdf'));
      final tries = <(String, List<String>)>[
        for (final exe in _officeExes()) (exe, ['--headless', '--convert-to', 'pdf', '--outdir', tmp.path, input.path]),
        if (Platform.isLinux)
          ('flatpak', ['run', 'org.libreoffice.LibreOffice', '--headless', '--convert-to', 'pdf', '--outdir', tmp.path, input.path]),
        if (Platform.isWindows) ('powershell', ['-NoProfile', '-Command', _powerPointScript(input.path, out.path)]),
      ];
      for (final (exe, args) in tries) {
        try {
          await Process.run(exe, args).timeout(const Duration(minutes: 3));
        } catch (_) {
          continue;
        }
        if (await out.exists() && await out.length() > 0) return await out.readAsBytes();
      }
      return null;
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  static List<String> _officeExes() {
    if (Platform.isWindows) {
      return [
        for (final base in [Platform.environment['ProgramFiles'], Platform.environment['ProgramFiles(x86)']])
          if (base != null) p.join(base, 'LibreOffice', 'program', 'soffice.exe'),
        'soffice',
      ];
    }
    return ['soffice', 'libreoffice', '/snap/bin/libreoffice'];
  }

  /// En Windows con PowerPoint (o Word) instalado: guardar como PDF.
  static String _powerPointScript(String input, String output) {
    final i = input.replaceAll("'", "''");
    final o = output.replaceAll("'", "''");
    final ext = p.extension(input).toLowerCase();
    if (['.doc', '.docx', '.odt', '.rtf'].contains(ext)) {
      return "\$w = New-Object -ComObject Word.Application; \$d = \$w.Documents.Open('$i', \$false, \$true); "
          "\$d.SaveAs2('$o', 17); \$d.Close(\$false); \$w.Quit()";
    }
    return "\$a = New-Object -ComObject PowerPoint.Application; "
        "\$d = \$a.Presentations.Open('$i', \$true, \$false, \$false); "
        "\$d.SaveAs('$o', 32); \$d.Close(); \$a.Quit()";
  }

  static bool _isPdf(Uint8List b) => b.length > 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46;

  static bool _looksLikeHtml(Uint8List b) {
    final head = String.fromCharCodes(b.take(200)).trimLeft().toLowerCase();
    return head.startsWith('<!doctype html') || head.startsWith('<html');
  }

  static String _nameFrom(Uri u, http.Response res) {
    final cd = res.headers['content-disposition'] ?? '';
    final m = RegExp(r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''', caseSensitive: false).firstMatch(cd);
    if (m != null) return Uri.decodeComponent(m.group(1)!);
    final type = res.headers['content-type'] ?? '';
    if (type.contains('presentationml')) return 'documento.pptx';
    if (type.contains('wordprocessingml')) return 'documento.docx';
    if (type.contains('spreadsheetml')) return 'documento.xlsx';
    if (type.contains('image/png')) return 'imagen.png';
    if (type.contains('image/jpeg')) return 'imagen.jpg';
    return u.pathSegments.isEmpty ? 'documento' : u.pathSegments.last;
  }
}

/// Enlace de Google (Slides, Docs, Sheets o un archivo de Drive) → enlace
/// para bajarlo como PDF. null si no es de Google.
Uri? googleExportUrl(Uri u) {
  final id = RegExp(r'/d/([a-zA-Z0-9_-]{10,})').firstMatch(u.path)?.group(1) ?? u.queryParameters['id'];
  if (id == null) return null;
  if (u.host == 'docs.google.com') {
    if (u.path.startsWith('/presentation/')) return Uri.parse('https://docs.google.com/presentation/d/$id/export/pdf');
    if (u.path.startsWith('/document/')) return Uri.parse('https://docs.google.com/document/d/$id/export?format=pdf');
    if (u.path.startsWith('/spreadsheets/')) {
      return Uri.parse('https://docs.google.com/spreadsheets/d/$id/export?format=pdf');
    }
  }
  if (u.host == 'drive.google.com') return Uri.parse('https://drive.google.com/uc?export=download&id=$id');
  return null;
}
