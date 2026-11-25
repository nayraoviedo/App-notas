import 'package:flutter/material.dart';

import '../../../../core/fonts.dart';
import '../../domain/practice.dart';

/// Configurar una práctica de caligrafía china: qué caracteres, cuadrícula,
/// fuente del modelo, cuántas copias para calcar y tamaño de los cuadros.
Future<PracticeSheet?> showPracticeSheetDialog(BuildContext context, {PracticeSheet? initial}) {
  return showModalBottomSheet<PracticeSheet>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: _PracticeForm(initial: initial),
      ),
    ),
  );
}

class _PracticeForm extends StatefulWidget {
  const _PracticeForm({this.initial});
  final PracticeSheet? initial;

  @override
  State<_PracticeForm> createState() => _PracticeFormState();
}

class _PracticeFormState extends State<_PracticeForm> {
  late List<PracticeChar> _chars = widget.initial?.chars ?? practiceSets.first.chars;
  late String? _setName = widget.initial == null ? practiceSets.first.name : null;
  late final _custom = TextEditingController(
      text: widget.initial == null ? '' : widget.initial!.chars.map((c) => c.char).join());
  late PracticeGrid _grid = widget.initial?.grid ?? PracticeGrid.tianzi;
  late String _font = widget.initial?.font ?? practiceFonts.first.$1;
  late int _trace = widget.initial?.traceCount ?? 3;
  late double _cell = widget.initial?.cellSize ?? 84;
  late bool _pinyin = widget.initial?.showPinyin ?? true;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sample = _chars.isEmpty ? '永' : _chars.first.char;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                Text('Práctica de caligrafía china', style: text.titleLarge),
                const SizedBox(height: 4),
                const Text(
                  'Cada fila tiene el carácter modelo, copias tenues para calcar '
                  'y cuadros vacíos para escribirlo solo.',
                ),
                const SizedBox(height: 16),
                Text('Caracteres', style: text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final set in practiceSets)
                      ChoiceChip(
                        label: Text('${set.name} ${set.chars.take(3).map((c) => c.char).join()}'),
                        selected: _setName == set.name,
                        onSelected: (_) => setState(() {
                          _setName = set.name;
                          _chars = set.chars;
                        }),
                      ),
                    ChoiceChip(
                      label: const Text('Mis caracteres'),
                      selected: _setName == null,
                      onSelected: (_) => setState(() {
                        _setName = null;
                        _chars = charsFromText(_custom.text);
                      }),
                    ),
                  ],
                ),
                if (_setName == null) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _custom,
                    style: fontStyle(_font, size: 24),
                    decoration: const InputDecoration(
                      labelText: 'Escribe o pega los caracteres',
                      hintText: '例如：学习中文',
                      helperText: 'Un carácter por fila. Puedes usar el teclado chino (pinyin).',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (t) => setState(() => _chars = charsFromText(t)),
                  ),
                ],
                const SizedBox(height: 8),
                if (_chars.isNotEmpty)
                  Text(
                    _chars.map((c) => c.char).join(' '),
                    style: fontStyle(_font, size: 26),
                  ),
                const SizedBox(height: 20),
                Text('Cuadrícula', style: text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final g in PracticeGrid.values)
                      ChoiceChip(
                        label: Text('${g.hanzi} · ${g.label}'),
                        selected: _grid == g,
                        onSelected: (_) => setState(() => _grid = g),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Letra del modelo', style: text.titleSmall),
                for (final (family, label) in practiceFonts)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: family,
                    groupValue: _font,
                    onChanged: (v) => setState(() => _font = v!),
                    title: Text(label),
                    secondary: Text(sample, style: fontStyle(family, size: 30)),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Text('Copias para calcar')),
                    Text('$_trace'),
                  ],
                ),
                Slider(
                  min: 0,
                  max: 8,
                  divisions: 8,
                  value: _trace.toDouble(),
                  onChanged: (v) => setState(() => _trace = v.round()),
                ),
                Row(
                  children: [
                    const Expanded(child: Text('Tamaño del cuadro')),
                    Text(_cell < 75 ? 'Pequeño' : (_cell < 100 ? 'Mediano' : 'Grande')),
                  ],
                ),
                Slider(
                  min: 60,
                  max: 130,
                  value: _cell,
                  onChanged: (v) => setState(() => _cell = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mostrar pinyin y significado'),
                  subtitle: const Text('Solo en los ejemplos que los traen'),
                  value: _pinyin,
                  onChanged: (v) => setState(() => _pinyin = v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: Text(_chars.isEmpty
                    ? 'Crear cuadrícula vacía'
                    : 'Crear práctica (${_chars.length} caracteres)'),
                onPressed: () => Navigator.pop(
                  context,
                  PracticeSheet(
                    chars: _chars,
                    grid: _grid,
                    font: _font,
                    traceCount: _trace,
                    cellSize: _cell,
                    showPinyin: _pinyin,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
