import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Recorte de pantalla en la compu con la herramienta del sistema:
/// - Linux: gnome-screenshot (o Spectacle / scrot), eliges el área con el
///   mouse.
/// - Windows: la herramienta Recortes (Win+Shift+S); la imagen se toma del
///   portapapeles.
/// Devuelve la ruta de la imagen, o null si se canceló.
Future<String?> captureScreenRegion() async {
  final out = '${(await getTemporaryDirectory()).path}/recorte_${DateTime.now().millisecondsSinceEpoch}.png';
  if (Platform.isLinux) {
    final tools = <(String, List<String>)>[
      ('gnome-screenshot', ['-a', '-f', out]),
      ('spectacle', ['-r', '-b', '-n', '-o', out]),
      ('scrot', ['-s', '-o', out]),
    ];
    var found = false;
    for (final (cmd, args) in tools) {
      try {
        final r = await Process.run(cmd, args);
        found = true;
        if (r.exitCode == 0 && File(out).existsSync() && File(out).lengthSync() > 0) return out;
        // Se canceló (Esc) o falló esta herramienta: no probar otra.
        return null;
      } on ProcessException {
        continue; // no está instalada
      }
    }
    if (!found) {
      throw const ScreenCaptureException(
          'Para recortar la pantalla instala la herramienta de capturas:\nsudo apt install gnome-screenshot');
    }
    return null;
  }
  if (Platform.isWindows) {
    final safe = out.replaceAll("'", "''");
    final script = '''
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Clipboard]::Clear()
Start-Process 'ms-screenclip:'
\$end = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt \$end) {
  Start-Sleep -Milliseconds 400
  if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
    \$img = [System.Windows.Forms.Clipboard]::GetImage()
    \$img.Save('$safe', [System.Drawing.Imaging.ImageFormat]::Png)
    exit 0
  }
}
exit 1
''';
    final r = await Process.run('powershell', ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-Command', script]);
    if (r.exitCode == 0 && File(out).existsSync()) return out;
    return null;
  }
  if (Platform.isMacOS) {
    final r = await Process.run('screencapture', ['-i', out]);
    if (r.exitCode == 0 && File(out).existsSync()) return out;
    return null;
  }
  throw const ScreenCaptureException('Recortar la pantalla no está disponible aquí.');
}

class ScreenCaptureException implements Exception {
  const ScreenCaptureException(this.message);
  final String message;
  @override
  String toString() => message;
}
