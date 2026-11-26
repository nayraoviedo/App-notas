import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/drawing.dart';
import 'drawing_store.dart';

/// Una plantilla propia: una hoja guardada para empezar otras iguales
/// (horario, planner, hoja de ejercicios…).
class PageTemplate {
  const PageTemplate(this.name, this.path);
  final String name;
  final String path;
}

/// Plantillas propias, como archivos en la carpeta "plantillas" (entran en
/// la copia de seguridad junto con lo demás).
class PageTemplates {
  static Future<Directory> _dir() async {
    final d = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'plantillas'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<List<PageTemplate>> list() async {
    try {
      final d = await _dir();
      final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      return [for (final f in files) PageTemplate(p.basenameWithoutExtension(f.path), f.path)];
    } catch (_) {
      return const [];
    }
  }

  /// Guarda la hoja tal como está (sin pestaña ni marcador).
  static Future<void> save(String name, Drawing d) async {
    final safe = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    final dir = await _dir();
    await DrawingStore().save(p.join(dir.path, '$safe.json'), d.copyWith(bookmarked: false, clearTab: true));
  }

  static Future<Drawing> load(PageTemplate t) => DrawingStore().load(t.path);

  static Future<void> delete(PageTemplate t) async {
    try {
      await File(t.path).delete();
    } catch (_) {}
  }
}
