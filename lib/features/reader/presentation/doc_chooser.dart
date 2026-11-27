import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers.dart';
import '../../settings/settings.dart';
import '../data/doc_source.dart';

String _recentKey(String noteId) => 'doc.recent.$noteId';
String _nameKey(String docPath) => 'doc.name.${p.basenameWithoutExtension(docPath)}';

/// Nombre con que se muestra el documento (el del archivo original).
String docTitle(SharedPreferences prefs, String docPath) => prefs.getString(_nameKey(docPath)) ?? 'Documento';

/// Documentos abiertos en esta nota, el último primero (máximo 6).
List<String> recentDocs(SharedPreferences prefs, String noteId) => [
      for (final d in prefs.getStringList(_recentKey(noteId)) ?? const <String>[])
        if (File(d).existsSync()) d,
    ];

Future<void> rememberRecentDoc(SharedPreferences prefs, String noteId, String docPath) async {
  final list = [docPath, ...recentDocs(prefs, noteId).where((d) => d != docPath)].take(6).toList();
  await prefs.setStringList(_recentKey(noteId), list);
}

/// Elegir qué ver junto a las notas: un documento ya abierto en esta nota,
/// un archivo (PDF, PowerPoint, Word, imagen…) o un enlace (Google Slides…).
/// Devuelve la ruta del documento listo, o null.
Future<String?> chooseDocument(BuildContext context, WidgetRef ref, {required String noteId}) async {
  final prefs = ref.read(sharedPreferencesProvider);
  final recent = recentDocs(prefs, noteId);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final d in recent)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(docTitle(prefs, d), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Seguir donde te quedaste'),
              onTap: () => Navigator.pop(context, 'recent:$d'),
            ),
          if (recent.isNotEmpty) const Divider(),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Archivo'),
            subtitle: const Text('PDF, PowerPoint, Word o una imagen'),
            onTap: () => Navigator.pop(context, 'file'),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Enlace'),
            subtitle: const Text('Google Slides, Google Docs, Drive o un PDF de internet'),
            onTap: () => Navigator.pop(context, 'link'),
          ),
        ]),
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (choice.startsWith('recent:')) return choice.substring(7);

  final source = DocSource(ref.read(fileStorageProvider), prefs);
  String? name;
  Future<String> Function(void Function(String)) task;
  if (choice == 'file') {
    final picked = await source.pickFile();
    if (picked == null) return null;
    name = p.basenameWithoutExtension(picked);
    task = (onStatus) => source.fromFile(picked, onStatus: onStatus);
  } else {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    if (!context.mounted) return null;
    final c = TextEditingController(text: clip.startsWith('http') ? clip : '');
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enlace del documento'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'https://docs.google.com/presentation/…'),
          ),
          const SizedBox(height: 10),
          const Text(
            'En Google Slides o Docs, primero toca Compartir → "Cualquier persona con el enlace".',
            style: TextStyle(fontSize: 13),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Abrir')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return null;
    final u = Uri.tryParse(url);
    name = u?.host.contains('google') == true
        ? (u!.path.contains('presentation') ? 'Diapositivas de Google' : 'Documento de Google')
        : (u?.pathSegments.isNotEmpty == true ? p.basenameWithoutExtension(u!.pathSegments.last) : 'Documento');
    task = (onStatus) => source.fromUrl(url, onStatus: onStatus);
  }
  if (!context.mounted) return null;

  final status = ValueNotifier('Preparando…');
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 16),
        Expanded(child: ValueListenableBuilder<String>(valueListenable: status, builder: (_, s, __) => Text(s))),
      ]),
    ),
  );
  var shown = true;
  void close() {
    if (shown && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    shown = false;
  }

  try {
    final path = await task((s) => status.value = s);
    close();
    await prefs.setString(_nameKey(path), name);
    return path;
  } catch (e) {
    close();
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No se pudo abrir'),
          content: Text('$e'.replaceFirst('Exception: ', '')),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
        ),
      );
    }
    return null;
  } finally {
    status.dispose();
  }
}
