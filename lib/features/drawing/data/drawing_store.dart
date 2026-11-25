import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/drawing.dart';

/// Guarda cada hoja como un archivo JSON (los trazos pueden ser muchos, por
/// eso no van a la base de datos; la nota solo guarda la ruta).
class DrawingStore {
  Future<Drawing> load(String path) async {
    final file = File(path);
    if (!await file.exists()) return Drawing.blank();
    final text = await file.readAsString();
    // Decodificar en otro isolate para no trabar la pantalla con hojas grandes.
    final json = await compute(_decode, text);
    return Drawing.fromJson(json);
  }

  Future<void> save(String path, Drawing drawing) async {
    final text = jsonEncode(drawing.toJson());
    final tmp = File('$path.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(path); // escritura atómica: nunca queda un archivo a medias
  }

  static Map<String, Object?> _decode(String text) =>
      (jsonDecode(text) as Map).cast<String, Object?>();
}
