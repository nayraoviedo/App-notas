import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/notebook.dart';

class NotebookFormResult {
  const NotebookFormResult(this.name, this.color, this.coverPath, this.style);
  final String name;
  final int color;
  final String? coverPath;
  final CoverStyle style;
}

/// Crear o editar un cuaderno: nombre, color, dibujo, sticker y foto opcional.
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
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: _NotebookForm(initial: initial, pickCover: pickCover),
      ),
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
  late CoverStyle _style = widget.initial?.style ?? const CoverStyle();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                Text(widget.initial == null ? 'Nuevo cuaderno' : 'Editar cuaderno',
                    style: text.titleMedium),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NotebookCover(
                      name: _name.text,
                      color: _color,
                      coverPath: _cover,
                      style: _style,
                      width: 100,
                    ),
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
                                label: const Text('Foto de portada'),
                                onPressed: () async {
                                  final path = await widget.pickCover();
                                  if (path != null) setState(() => _cover = path);
                                },
                              ),
                              if (_cover != null)
                                TextButton(
                                  onPressed: () => setState(() => _cover = null),
                                  child: const Text('Quitar foto'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Color', style: text.titleSmall),
                const SizedBox(height: 8),
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
                              width: c == _color ? 3 : 1,
                              color: c == _color ? scheme.onSurface : Colors.black12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Dibujo', style: text.titleSmall),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: CoverPattern.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final p = CoverPattern.values[i];
                      final selected = p == _style.pattern;
                      return GestureDetector(
                        onTap: () => setState(() => _style = _style.copyWith(pattern: p)),
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  width: selected ? 3 : 0,
                                  color: selected ? scheme.primary : Colors.transparent,
                                ),
                              ),
                              child: NotebookCover(
                                name: '',
                                color: _color,
                                style: CoverStyle(pattern: p, sticker: ''),
                                width: 56,
                                showLabel: false,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(p.label, style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text('Sticker', style: text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in coverStickers)
                      ChoiceChip(
                        label: Text(s.isEmpty ? 'Ninguno' : s, style: const TextStyle(fontSize: 18)),
                        selected: _style.sticker == s,
                        onSelected: (_) => setState(() => _style = _style.copyWith(sticker: s)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _name.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(
                          context,
                          NotebookFormResult(_name.text.trim(), _color, _cover, _style),
                        ),
                child: const Text('Guardar'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Portada de cuaderno: color con dibujo (lunares, cuadritos…), lomo con
/// espiral, sticker y etiqueta con el nombre. O una foto.
class NotebookCover extends StatelessWidget {
  const NotebookCover({
    super.key,
    required this.name,
    required this.color,
    this.coverPath,
    this.style = const CoverStyle(),
    this.width = 120,
    this.icon,
    this.showLabel = true,
  });

  final String name;
  final int color;
  final String? coverPath;
  final CoverStyle style;
  final double width;
  final IconData? icon;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final c = Color(color);
    final height = width * 1.35;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.horizontal(
            left: Radius.circular(width * 0.04), right: Radius.circular(width * 0.12)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coverPath != null)
              Image.file(File(coverPath!), fit: BoxFit.cover)
            else
              CustomPaint(painter: _CoverPatternPainter(c, style.pattern)),
            // Lomo con anillos de espiral.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: width * 0.1,
              child: CustomPaint(painter: _SpiralPainter()),
            ),
            if (icon != null)
              Center(child: Icon(icon, color: Colors.white, size: width * 0.3)),
            if (style.sticker.isNotEmpty && icon == null)
              Positioned(
                right: width * 0.08,
                top: width * 0.1,
                child: Text(style.sticker, style: TextStyle(fontSize: width * 0.24)),
              ),
            if (showLabel)
              Positioned(
                left: width * 0.18,
                right: width * 0.08,
                bottom: height * 0.12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black12)],
                  ),
                  child: Text(
                    name.isEmpty ? 'Sin nombre' : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: (width * 0.11).clamp(9.0, 15.0),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CoverPatternPainter extends CustomPainter {
  _CoverPatternPainter(this.color, this.pattern);
  final Color color;
  final CoverPattern pattern;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final light = color.computeLuminance() > 0.5;
    final ink = Paint()
      ..color = (light ? Colors.white : Colors.white).withValues(alpha: light ? 0.75 : 0.35);
    final soft = Paint()..color = Colors.white.withValues(alpha: 0.35);
    final u = size.width / 8; // unidad del dibujo

    switch (pattern) {
      case CoverPattern.plain:
        break;
      case CoverPattern.dots:
        for (var y = u / 2, row = 0; y < size.height + u; y += u, row++) {
          for (var x = (row.isEven ? u / 2 : u); x < size.width + u; x += u) {
            canvas.drawCircle(Offset(x, y), u * 0.18, ink);
          }
        }
      case CoverPattern.gingham:
        for (var x = 0.0; x < size.width; x += u * 1.4) {
          canvas.drawRect(Rect.fromLTWH(x, 0, u * 0.7, size.height), soft);
        }
        for (var y = 0.0; y < size.height; y += u * 1.4) {
          canvas.drawRect(Rect.fromLTWH(0, y, size.width, u * 0.7), soft);
        }
      case CoverPattern.stripes:
        canvas.save();
        canvas.rotate(-math.pi / 4);
        for (var x = -size.height; x < size.width + size.height; x += u * 1.2) {
          canvas.drawRect(Rect.fromLTWH(x, -size.height, u * 0.5, size.height * 3), soft);
        }
        canvas.restore();
      case CoverPattern.hearts:
        for (var y = u, row = 0; y < size.height + u; y += u * 1.6, row++) {
          for (var x = (row.isEven ? u : u * 1.8); x < size.width + u; x += u * 1.6) {
            canvas.drawPath(_heart(Offset(x, y), u * 0.32), ink);
          }
        }
      case CoverPattern.stars:
        var seed = 7;
        double rnd() => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
        for (var i = 0; i < 26; i++) {
          final p = Offset(rnd() * size.width, rnd() * size.height);
          canvas.drawPath(_star(p, u * (0.15 + rnd() * 0.2)), ink);
        }
      case CoverPattern.clouds:
        for (var y = u * 1.2, row = 0; y < size.height + u; y += u * 2.4, row++) {
          for (var x = (row.isEven ? u : u * 2.4); x < size.width + u * 2; x += u * 3.2) {
            final c = Offset(x, y);
            canvas
              ..drawCircle(c, u * 0.45, ink)
              ..drawCircle(c + Offset(u * 0.45, u * 0.1), u * 0.38, ink)
              ..drawCircle(c + Offset(-u * 0.45, u * 0.12), u * 0.33, ink)
              ..drawRRect(
                  RRect.fromRectAndRadius(
                      Rect.fromCenter(center: c + Offset(0, u * 0.25), width: u * 1.5, height: u * 0.45),
                      Radius.circular(u)),
                  ink);
          }
        }
      case CoverPattern.checker:
        for (var y = 0, row = 0; y * u < size.height; y++, row++) {
          for (var x = 0; x * u < size.width; x++) {
            if ((x + row).isEven) {
              canvas.drawRect(Rect.fromLTWH(x * u, y * u, u, u), soft);
            }
          }
        }
    }
  }

  static Path _heart(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy + r * 0.9)
    ..cubicTo(c.dx - r * 1.6, c.dy - r * 0.2, c.dx - r * 0.6, c.dy - r * 1.4, c.dx, c.dy - r * 0.4)
    ..cubicTo(c.dx + r * 0.6, c.dy - r * 1.4, c.dx + r * 1.6, c.dy - r * 0.2, c.dx, c.dy + r * 0.9)
    ..close();

  static Path _star(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  bool shouldRepaint(_CoverPatternPainter old) =>
      old.color != color || old.pattern != pattern;
}

class _SpiralPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: 0.12));
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.18;
    final hole = Paint()..color = Colors.black.withValues(alpha: 0.25);
    final step = size.width * 1.4;
    for (var y = step / 2; y < size.height; y += step) {
      canvas.drawCircle(Offset(size.width * 0.75, y), size.width * 0.16, hole);
      canvas.drawArc(
        Rect.fromCenter(center: Offset(size.width * 0.35, y), width: size.width * 0.9, height: step * 0.45),
        math.pi * 0.5,
        math.pi,
        false,
        ring,
      );
    }
  }

  @override
  bool shouldRepaint(_SpiralPainter old) => false;
}
