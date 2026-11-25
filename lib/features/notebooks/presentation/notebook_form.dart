import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/notebook.dart';

class NotebookFormResult {
  const NotebookFormResult(this.name, this.color, this.coverPath);
  final String name;
  final int color;
  final String? coverPath;
}

/// Crear o editar un cuaderno: nombre, color y portada opcional.
Future<NotebookFormResult?> showNotebookForm(
  BuildContext context, {
  Notebook? initial,
  required Future<String?> Function() pickCover,
}) {
  return showModalBottomSheet<NotebookFormResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _NotebookForm(initial: initial, pickCover: pickCover),
    ),
  );
}

class _NotebookForm extends StatefulWidget {
  const _NotebookForm({this.initial, required this.pickCover});
  final Notebook? initial;
  final Future<String?> Function() pickCover;

  @override
  State<_NotebookForm> createState() => _NotebookFormState();
}

class _NotebookFormState extends State<_NotebookForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late int _color = widget.initial?.color ?? notebookColors.first;
  late String? _cover = widget.initial?.coverPath;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.initial == null ? 'Nuevo cuaderno' : 'Editar cuaderno',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NotebookCover(name: _name.text, color: _color, coverPath: _cover, width: 90),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _name,
                        autofocus: widget.initial == null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(labelText: 'Nombre'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Portada'),
                            onPressed: () async {
                              final path = await widget.pickCover();
                              if (path != null) setState(() => _cover = path);
                            },
                          ),
                          if (_cover != null)
                            TextButton(
                              onPressed: () => setState(() => _cover = null),
                              child: const Text('Quitar'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in notebookColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: c == _color ? 3 : 0,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _name.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(
                        context, NotebookFormResult(_name.text.trim(), _color, _cover)),
                child: const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Portada de cuaderno: color con lomo, o imagen, y el nombre.
class NotebookCover extends StatelessWidget {
  const NotebookCover({
    super.key,
    required this.name,
    required this.color,
    this.coverPath,
    this.width = 120,
    this.icon,
  });

  final String name;
  final int color;
  final String? coverPath;
  final double width;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = Color(color);
    return SizedBox(
      width: width,
      height: width * 1.35,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c,
          borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(4), right: Radius.circular(12)),
          boxShadow: const [
            BoxShadow(blurRadius: 6, offset: Offset(2, 3), color: Colors.black26),
          ],
          image: coverPath == null
              ? null
              : DecorationImage(image: FileImage(File(coverPath!)), fit: BoxFit.cover),
        ),
        child: Stack(
          children: [
            // Lomo del cuaderno.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: width * 0.08,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
            ),
            if (icon != null)
              Center(child: Icon(icon, color: Colors.white, size: width * 0.3)),
            Positioned(
              left: width * 0.14,
              right: 8,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  name.isEmpty ? 'Sin nombre' : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
