import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../domain/flashcard_import.dart';

const importFormatHelp = 'Una tarjeta por línea, con la pregunta y la respuesta separadas por punto y coma ( ; ):\n'
    '   ¿Capital de Bolivia? ; Sucre\n\n'
    'También sirve tabulación (copiar dos columnas de Excel o Google Sheets), barra | o ::\n\n'
    'O en bloques con P: y R: (la respuesta puede tener varias líneas):\n'
    '   P: ¿Qué es la mitosis?\n'
    '   R: División de una célula en dos iguales.';

/// Pegar texto o abrir un .txt/.csv y crear muchas tarjetas de una vez.
/// Funciona igual en el celular y en la compu.
Future<void> showImportFlashcards(BuildContext context, WidgetRef ref) async {
  final added = await showDialog<int>(context: context, builder: (_) => const _ImportDialog());
  if (added != null && added > 0 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added == 1 ? '1 tarjeta importada ✓' : '$added tarjetas importadas ✓')),
    );
  }
}

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _text = TextEditingController();
  final _deck = TextEditingController(text: 'General');
  FlashcardImportResult _parsed = const FlashcardImportResult([], []);
  bool _busy = false;
  String? _fileName;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() => _parsed = parseFlashcards(_text.text)));
  }

  @override
  void dispose() {
    _text.dispose();
    _deck.dispose();
    super.dispose();
  }

  Future<void> _openFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'csv', 'tsv'],
      withData: true,
    );
    final f = res?.files.singleOrNull;
    if (f == null) return;
    List<int>? bytes = f.bytes;
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null) return;
    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      // Archivos guardados desde Excel en Windows suelen venir en Latin-1.
      content = latin1.decode(bytes);
    }
    _text.text = content;
    setState(() {
      _fileName = f.name;
      final base = f.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      if (_deck.text.trim().isEmpty || _deck.text == 'General') _deck.text = base;
    });
  }

  Future<void> _import() async {
    final cards = _parsed.cards;
    if (cards.isEmpty) return;
    setState(() => _busy = true);
    final repo = ref.read(flashcardsRepositoryProvider);
    final deck = _deck.text.trim().isEmpty ? 'General' : _deck.text.trim();
    // No repetir las que ya están en ese mazo (importar el mismo archivo
    // dos veces) ni las repetidas dentro del mismo texto.
    final seen = await repo.existingPairs(deck);
    var added = 0;
    for (final c in cards) {
      if (!seen.add((c.front.trim(), c.back.trim()))) continue;
      await repo.add(front: c.front, back: c.back, deck: deck);
      added++;
    }
    if (mounted) {
      final dup = cards.length - added;
      if (dup > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(dup == 1 ? '1 tarjeta ya estaba en el mazo y se saltó' : '$dup tarjetas ya estaban en el mazo y se saltaron')));
      }
      Navigator.pop(context, added);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = _parsed.cards.length;
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: const Text('Importar preguntas y respuestas'),
      content: SizedBox(
        width: width > 700 ? 560 : width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(importFormatHelp, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _openFile,
                icon: const Icon(Icons.upload_file),
                label: Text(_fileName == null ? 'Abrir archivo .txt o .csv' : 'Archivo: $_fileName'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _text,
                minLines: 6,
                maxLines: 12,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '…o pega aquí tus preguntas',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _deck,
                decoration: const InputDecoration(labelText: 'Mazo (tema)'),
              ),
              const SizedBox(height: 12),
              Text(
                n == 0
                    ? 'Todavía no hay tarjetas para importar.'
                    : n == 1
                        ? 'Se va a crear 1 tarjeta.'
                        : 'Se van a crear $n tarjetas.',
                style: TextStyle(fontWeight: FontWeight.bold, color: n == 0 ? null : scheme.primary),
              ),
              if (_parsed.skipped.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_parsed.skipped.length} línea(s) sin separador se saltan, por ejemplo: '
                    '"${_parsed.skipped.first.length > 60 ? '${_parsed.skipped.first.substring(0, 60)}…' : _parsed.skipped.first}"',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ),
              for (final c in _parsed.cards.take(3))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.style_outlined, size: 20),
                  title: Text(c.front, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(c.back.isEmpty ? '(sin respuesta)' : c.back,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              if (n > 3) Text('…y ${n - 3} más', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _busy || n == 0 ? null : _import,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(n == 0 ? 'Importar' : 'Importar $n'),
        ),
      ],
    );
  }
}
