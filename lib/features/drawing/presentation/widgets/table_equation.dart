import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

// ------------------------------------------------------------------ Datos

/// Tabla: celdas (filas × columnas), primera fila como encabezado y color.
class TableData {
  const TableData({required this.cells, this.header = true, this.color = 0xFFB8D8F2});
  final List<List<String>> cells;
  final bool header;
  final int color;

  int get rows => cells.length;
  int get cols => cells.isEmpty ? 0 : cells.first.length;

  factory TableData.empty(int rows, int cols) =>
      TableData(cells: [for (var r = 0; r < rows; r++) [for (var c = 0; c < cols; c++) '']]);

  /// Cambia el tamaño conservando lo escrito.
  TableData resized(int rows, int cols) => TableData(
        header: header,
        color: color,
        cells: [
          for (var r = 0; r < rows; r++)
            [for (var c = 0; c < cols; c++) r < this.rows && c < this.cols ? cells[r][c] : ''],
        ],
      );

  String encode() => jsonEncode({'kind': 'table', 'cells': cells, 'header': header, 'color': color});
}

/// Ecuación en LaTeX (lo que entiende el dibujante de fórmulas).
class EquationData {
  const EquationData(this.tex, {this.color = 0xFF1F2328, this.size = 34});
  final String tex;
  final int color;
  final double size;
  String encode() => jsonEncode({'kind': 'eq', 'tex': tex, 'color': color, 'size': size});
}

/// Lee los datos guardados en una imagen de la hoja (tabla o ecuación).
Object? decodeSource(String? src) {
  if (src == null) return null;
  try {
    final j = jsonDecode(src) as Map<String, Object?>;
    if (j['kind'] == 'table') {
      return TableData(
        cells: [for (final r in j['cells'] as List) [for (final c in r as List) '$c']],
        header: j['header'] as bool? ?? true,
        color: j['color'] as int? ?? 0xFFB8D8F2,
      );
    }
    if (j['kind'] == 'eq') {
      return EquationData(j['tex'] as String? ?? '',
          color: j['color'] as int? ?? 0xFF1F2328, size: (j['size'] as num?)?.toDouble() ?? 34);
    }
  } catch (_) {}
  return null;
}

// ------------------------------------------------------------ Cómo se ven

class TableView extends StatelessWidget {
  const TableView(this.data, {super.key, this.fontSize = 20});
  final TableData data;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final head = Color(data.color);
    const ink = Color(0xFF2B2B2B);
    return Container(
      color: Colors.white,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: const Color(0xFF5C4A40), width: 1.4),
        children: [
          for (final (r, row) in data.cells.indexed)
            TableRow(
              decoration: BoxDecoration(color: data.header && r == 0 ? head : Colors.white),
              children: [
                for (final cell in row)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 70, maxWidth: 260),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Text(
                        cell,
                        style: TextStyle(
                          fontSize: fontSize,
                          color: ink,
                          fontWeight: data.header && r == 0 ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class EquationView extends StatelessWidget {
  const EquationView(this.data, {super.key});
  final EquationData data;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Math.tex(
          data.tex.trim().isEmpty ? r'\square' : data.tex,
          mathStyle: MathStyle.display,
          textStyle: TextStyle(fontSize: data.size, color: Color(data.color)),
          onErrorFallback: (e) => Text('Revisa la ecuación: ${e.message}',
              style: const TextStyle(color: Colors.red, fontSize: 14)),
        ),
      );
}

/// Dibuja un widget fuera de la pantalla y lo convierte en PNG (para ponerlo
/// en la hoja como imagen; se ve igual en el PDF y en las miniaturas).
Future<(Uint8List, Size)> renderWidgetToPng(BuildContext context, Widget child, {double pixelRatio = 3}) async {
  final key = GlobalKey();
  final completer = Completer<(Uint8List, Size)>();
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -20000,
      top: 0,
      child: Material(
        type: MaterialType.transparency,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: RepaintBoundary(key: key, child: UnconstrainedBox(child: child)),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      // Un cuadro más para que carguen letras y fórmulas.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final size = Size(image.width / pixelRatio, image.height / pixelRatio);
      image.dispose();
      completer.complete((data!.buffer.asUint8List(), size));
    } catch (e, st) {
      completer.completeError(e, st);
    } finally {
      entry.remove();
    }
  });
  WidgetsBinding.instance.scheduleFrame();
  return completer.future;
}

// ------------------------------------------------------------- Editores

const _tableColors = [0xFFB8D8F2, 0xFFF7B6C8, 0xFFBFE3B4, 0xFFFFE08A, 0xFFD9C6F2, 0xFFF9C99A, 0xFFE6E6E6];

/// Crear o editar una tabla. Devuelve null si se cancela.
Future<TableData?> editTable(BuildContext context, [TableData? initial]) async {
  var start = initial;
  if (start == null) {
    final size = await _askSize(context);
    if (size == null || !context.mounted) return null;
    start = TableData.empty(size.$1, size.$2);
  }
  return Navigator.of(context).push<TableData>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _TableEditor(initial: start!),
  ));
}

/// "¿Cuántas filas y columnas?"
Future<(int, int)?> _askSize(BuildContext context) {
  final rows = TextEditingController(text: '3');
  final cols = TextEditingController(text: '3');
  return showDialog<(int, int)>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nueva tabla'),
      content: Row(
        children: [
          Expanded(
            child: TextField(
              controller: rows,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Filas', helperText: '1 a 30'),
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('×')),
          Expanded(
            child: TextField(
              controller: cols,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Columnas', helperText: '1 a 8'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final r = (int.tryParse(rows.text.trim()) ?? 3).clamp(1, 30);
            final c = (int.tryParse(cols.text.trim()) ?? 3).clamp(1, 8);
            Navigator.pop(context, (r, c));
          },
          child: const Text('Crear'),
        ),
      ],
    ),
  );
}

class _TableEditor extends StatefulWidget {
  const _TableEditor({required this.initial});
  final TableData initial;

  @override
  State<_TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<_TableEditor> {
  late TableData _data = widget.initial;
  final _ctls = <String, TextEditingController>{};

  TextEditingController _ctl(int r, int c) =>
      _ctls.putIfAbsent('$r-$c', () => TextEditingController(text: _data.cells[r][c]));

  TableData _collect() => TableData(
        header: _data.header,
        color: _data.color,
        cells: [
          for (var r = 0; r < _data.rows; r++) [for (var c = 0; c < _data.cols; c++) _ctl(r, c).text.trim()],
        ],
      );

  /// Borrar una fila o una columna (con lo que tenga escrito).
  void _remove({int? row, int? col}) {
    final cur = _collect();
    if ((row != null && cur.rows <= 1) || (col != null && cur.cols <= 1)) return;
    for (final c in _ctls.values) {
      c.dispose();
    }
    _ctls.clear();
    setState(() => _data = TableData(
          header: cur.header,
          color: cur.color,
          cells: [
            for (var r = 0; r < cur.rows; r++)
              if (r != row) [for (var c = 0; c < cur.cols; c++) if (c != col) cur.cells[r][c]],
          ],
        ));
  }

  void _resize(int rows, int cols) {
    if (rows < 1 || cols < 1 || rows > 30 || cols > 8) return;
    final cur = _collect();
    for (final c in _ctls.values) {
      c.dispose();
    }
    _ctls.clear();
    setState(() => _data = cur.resized(rows, cols));
  }

  @override
  void dispose() {
    for (final c in _ctls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget stepper(String label, int v, void Function(int) on) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => on(v - 1)),
            Text('$v', style: const TextStyle(fontSize: 18)),
            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => on(v + 1)),
          ],
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tabla'),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context, _collect()), child: const Text('Listo')),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              stepper('Filas', _data.rows, (v) => _resize(v, _data.cols)),
              stepper('Columnas', _data.cols, (v) => _resize(_data.rows, v)),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Primera fila como título'),
            value: _data.header,
            onChanged: (v) => setState(() => _data = TableData(cells: _collect().cells, header: v, color: _data.color)),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final c in _tableColors)
                GestureDetector(
                  onTap: () => setState(() => _data = TableData(cells: _collect().cells, header: _data.header, color: c)),
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Color(c),
                    child: c == _data.color ? const Icon(Icons.check, size: 16, color: Colors.black54) : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(130),
              columnWidths: const {0: FixedColumnWidth(40)},
              border: const TableBorder(
                horizontalInside: BorderSide(color: Colors.black26),
                verticalInside: BorderSide(color: Colors.black26),
              ),
              children: [
                // Fila de botones para borrar columnas.
                TableRow(children: [
                  const SizedBox(),
                  for (var c = 0; c < _data.cols; c++)
                    IconButton(
                      tooltip: 'Borrar columna ${c + 1}',
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.black45),
                      onPressed: _data.cols > 1 ? () => _remove(col: c) : null,
                    ),
                ]),
                for (var r = 0; r < _data.rows; r++)
                  TableRow(
                    decoration: BoxDecoration(color: _data.header && r == 0 ? Color(_data.color) : null),
                    children: [
                      IconButton(
                        tooltip: 'Borrar fila ${r + 1}',
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.black45),
                        onPressed: _data.rows > 1 ? () => _remove(row: r) : null,
                      ),
                      for (var c = 0; c < _data.cols; c++)
                        TextField(
                          controller: _ctl(r, c),
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(fontWeight: _data.header && r == 0 ? FontWeight.w700 : null),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.all(8),
                            hintText: _data.header && r == 0 ? 'Título' : '',
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Después puedes moverla, agrandarla o tocarla para editarla otra vez.',
              style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

/// Botones para armar fórmulas sin saber LaTeX: (lo que se ve, lo que se
/// escribe, cuántos caracteres retroceder el cursor para escribir adentro).
const _eqButtons = <(String, String, int)>[
  ('a/b', r'\frac{}{}', 3),
  ('√', r'\sqrt{}', 1),
  ('ⁿ√', r'\sqrt[]{}', 3),
  ('xⁿ', '^{}', 1),
  ('xₙ', '_{}', 1),
  ('( )', r'\left(  \right)', 8),
  ('Σ', r'\sum_{i=1}^{n} ', 0),
  ('∫', r'\int_{a}^{b} ', 0),
  ('lím', r'\lim_{x \to } ', 2),
  ('π', r'\pi ', 0),
  ('θ', r'\theta ', 0),
  ('α', r'\alpha ', 0),
  ('β', r'\beta ', 0),
  ('Δ', r'\Delta ', 0),
  ('∞', r'\infty ', 0),
  ('±', r'\pm ', 0),
  ('×', r'\times ', 0),
  ('÷', r'\div ', 0),
  ('·', r'\cdot ', 0),
  ('≤', r'\le ', 0),
  ('≥', r'\ge ', 0),
  ('≠', r'\neq ', 0),
  ('≈', r'\approx ', 0),
  ('→', r'\to ', 0),
  ('°', r'^{\circ}', 0),
  ('sen', r'\sin ', 0),
  ('cos', r'\cos ', 0),
  ('log', r'\log ', 0),
  ('vector', r'\vec{}', 1),
  ('matriz', r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}', 0),
  ('sistema', r'\begin{cases} x + y = 1 \\ x - y = 0 \end{cases}', 0),
];

const _eqExamples = <(String, String)>[
  ('Fórmula general', r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}'),
  ('Pitágoras', r'a^2 + b^2 = c^2'),
  ('Área del círculo', r'A = \pi r^2'),
  ('Derivada', r"f'(x) = \lim_{h \to 0} \frac{f(x+h) - f(x)}{h}"),
];

/// Crear o editar una ecuación.
Future<EquationData?> editEquation(BuildContext context, [EquationData? initial]) =>
    Navigator.of(context).push<EquationData>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _EquationEditor(initial: initial ?? const EquationData('')),
    ));

class _EquationEditor extends StatefulWidget {
  const _EquationEditor({required this.initial});
  final EquationData initial;

  @override
  State<_EquationEditor> createState() => _EquationEditorState();
}

class _EquationEditorState extends State<_EquationEditor> {
  late final _tex = TextEditingController(text: widget.initial.tex)..addListener(() => setState(() {}));
  late int _color = widget.initial.color;

  @override
  void dispose() {
    _tex.dispose();
    super.dispose();
  }

  void _insert(String text, int back) {
    final sel = _tex.selection;
    final t = _tex.text;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    final next = t.replaceRange(start, end, text);
    _tex.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length - back),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = EquationData(_tex.text, color: _color);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ecuación'),
        actions: [
          FilledButton(
            onPressed: _tex.text.trim().isEmpty ? null : () => Navigator.pop(context, data),
            child: const Text('Listo'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 110),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: EquationView(data)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tex,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: r'Ej.: x^2 + 3x = \frac{1}{2}',
              helperText: 'Usa los botones; donde quede el cursor, escribe lo de adentro.',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, tex, back) in _eqButtons)
                ActionChip(label: Text(label), onPressed: () => _insert(tex, back)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              for (final c in [0xFF1F2328, 0xFF1677FF, 0xFFE5484D, 0xFF2F9E44, 0xFF8A3B22, 0xFF6E3B8F])
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(c),
                    child: c == _color ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Ejemplos', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final (name, tex) in _eqExamples)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(name),
              subtitle: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(tex, textStyle: const TextStyle(fontSize: 18)),
              ),
              onTap: () => _tex.text = tex,
            ),
        ],
      ),
    );
  }
}
