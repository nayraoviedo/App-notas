import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/fonts.dart';
import '../../application/drawing_controller.dart';
import '../../domain/drawing.dart';
import '../painters/shape_painter.dart';
import '../painters/sticker_painter.dart';

/// Lo que se ve de un elemento (texto o foto), sin posición ni giro.
class CanvasItemContent extends StatelessWidget {
  const CanvasItemContent({super.key, required this.item});
  final CanvasItem item;

  @override
  Widget build(BuildContext context) => switch (item) {
        TextItem t => _TextContent(item: t),
        ImageItem i => _ImageContent(item: i),
        StickerItem st => SizedBox(
            width: st.width,
            height: st.height,
            child: CustomPaint(painter: StickerPainter(st.sticker)),
          ),
        ShapeItem sh => Padding(
            // Margen para que el borde de selección no tape el trazo.
            padding: EdgeInsets.all(sh.strokeWidth / 2 + 6),
            child: SizedBox(
              width: sh.width,
              height: sh.height,
              child: CustomPaint(
                painter: ShapePainter(
                  sh.shape,
                  color: Color(sh.color),
                  strokeWidth: sh.strokeWidth,
                  fill: sh.fill == null ? null : Color(sh.fill!),
                ),
              ),
            ),
          ),
      };
}

TextStyle textItemStyle(TextItem t) => fontStyle(t.font, size: t.size).copyWith(
      color: Color(t.color),
      fontWeight: t.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
      height: t.lineHeight,
      decoration: TextDecoration.combine([
        if (t.underline) TextDecoration.underline,
        if (t.strike) TextDecoration.lineThrough,
      ]),
      decorationColor: Color(t.color),
    );

/// Margen interno del texto cuando tiene fondo tipo etiqueta.
EdgeInsets textItemPadding(TextItem t) => t.background == null
    ? EdgeInsets.zero
    : EdgeInsets.symmetric(horizontal: t.size * 0.45, vertical: t.size * 0.2);

/// Tamaño que ocupa el texto (sin escala), para ubicarlo al editarlo.
Size measureTextItem(TextItem t) {
  final pad = textItemPadding(t);
  final tp = TextPainter(
    text: TextSpan(text: t.text.isEmpty ? ' ' : t.text, style: textItemStyle(t)),
    textAlign: textItemAlign(t),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: t.width - pad.horizontal);
  final size = Size(tp.width + pad.horizontal, tp.height + pad.vertical);
  tp.dispose();
  return size;
}

TextAlign textItemAlign(TextItem t) => switch (t.align) {
      TextItemAlign.left => TextAlign.left,
      TextItemAlign.center => TextAlign.center,
      TextItemAlign.right => TextAlign.right,
    };

class _TextContent extends StatelessWidget {
  const _TextContent({required this.item});
  final TextItem item;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      item.text.isEmpty ? ' ' : item.text,
      style: textItemStyle(item),
      textAlign: textItemAlign(item),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: item.width),
      child: item.background == null
          ? text
          : Container(
              padding: EdgeInsets.symmetric(
                  horizontal: item.size * 0.45, vertical: item.size * 0.2),
              decoration: BoxDecoration(
                color: Color(item.background!),
                borderRadius: BorderRadius.circular(item.size * 0.2),
              ),
              child: text,
            ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  const _ImageContent({required this.item});
  final ImageItem item;

  @override
  Widget build(BuildContext context) {
    final img = Image.file(
      File(item.path),
      width: item.width,
      height: item.height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: item.width,
        height: item.height,
        color: Colors.black12,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
    switch (item.frame) {
      case ImageFrame.none:
        return img;
      case ImageFrame.rounded:
        return ClipRRect(borderRadius: BorderRadius.circular(28), child: img);
      case ImageFrame.polaroid:
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(blurRadius: 10, offset: Offset(2, 4), color: Colors.black26)],
          ),
          child: img,
        );
      case ImageFrame.tape:
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Padding(padding: const EdgeInsets.only(top: 14), child: img),
            Transform.rotate(
              angle: -0.06,
              child: Container(
                width: item.width * 0.35,
                height: 34,
                color: const Color(0xFFF6D7A7).withValues(alpha: 0.85),
              ),
            ),
          ],
        );
    }
  }
}

/// Coloca un elemento en la hoja: centro en (x, y), con escala y giro.
class PositionedItem extends StatelessWidget {
  const PositionedItem({super.key, required this.item, required this.child});
  final CanvasItem item;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
        left: item.x,
        top: item.y,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: Transform.rotate(
            angle: item.rotation,
            child: Transform.scale(scale: item.scale, child: child),
          ),
        ),
      );
}

/// Elemento editable: tocar para seleccionar, arrastrar para mover y usar la
/// esquina para agrandar/achicar y girar.
class EditableCanvasItem extends StatefulWidget {
  const EditableCanvasItem({
    super.key,
    required this.item,
    required this.controller,
    required this.pageKey,
    required this.onEditText,
    required this.onPointerDown,
  });

  final CanvasItem item;
  final DrawingController controller;

  /// Clave de la hoja, para pasar posiciones de pantalla a la hoja.
  final GlobalKey pageKey;
  final void Function(TextItem item) onEditText;

  /// Avisa a la hoja que el toque fue sobre un elemento.
  final VoidCallback onPointerDown;

  @override
  State<EditableCanvasItem> createState() => _EditableCanvasItemState();
}

class _EditableCanvasItemState extends State<EditableCanvasItem> {
  Offset _grab = Offset.zero;
  Offset _v0 = const Offset(1, 0);
  double _s0 = 1;
  double _r0 = 0;

  CanvasItem get item => widget.item;
  bool get selected => widget.controller.selectedItemId == item.id;

  Offset? _toPage(Offset global) {
    final box = widget.pageKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  Offset get _center => Offset(item.x, item.y);

  void _select() {
    if (!selected) widget.controller.selectItem(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inv = 1 / item.scale;

    final content = Container(
      decoration: selected
          ? BoxDecoration(border: Border.all(color: scheme.primary, width: 2 * inv))
          : null,
      child: CanvasItemContent(item: item),
    );

    return PositionedItem(
      item: item,
      child: Listener(
        onPointerDown: (_) => widget.onPointerDown(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final t = item;
            if (selected && t is TextItem) {
              widget.onEditText(t);
            } else {
              _select();
            }
          },
          onDoubleTap: () {
            final t = item;
            if (t is TextItem) widget.onEditText(t);
          },
          onPanStart: (d) {
            _select();
            final p = _toPage(d.globalPosition);
            if (p == null) return;
            widget.controller.beginItemChange();
            _grab = p - _center;
          },
          onPanUpdate: (d) {
            final p = _toPage(d.globalPosition);
            if (p == null) return;
            final c = p - _grab;
            widget.controller.updateItem(item.id, (it) => it.moved(x: c.dx, y: c.dy),
                undoable: false);
          },
          child: Stack(
            children: [
              content,
              if (selected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Transform.scale(
                    scale: inv,
                    alignment: Alignment.bottomRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) {
                        final p = _toPage(d.globalPosition);
                        if (p == null) return;
                        widget.controller.beginItemChange();
                        _v0 = p - _center;
                        _s0 = item.scale;
                        _r0 = item.rotation;
                      },
                      onPanUpdate: (d) {
                        final p = _toPage(d.globalPosition);
                        if (p == null || _v0.distance < 1) return;
                        final v = p - _center;
                        final scale = (_s0 * v.distance / _v0.distance).clamp(0.15, 8.0);
                        final rot = _r0 + math.atan2(v.dy, v.dx) - math.atan2(_v0.dy, _v0.dx);
                        widget.controller.updateItem(
                          item.id,
                          (it) => it.moved(scale: scale, rotation: rot),
                          undoable: false,
                        );
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(Icons.open_with, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hoja de solo lectura con capas, textos y fotos (miniaturas y vistas previas).
class DrawingLayersStaticView extends StatelessWidget {
  const DrawingLayersStaticView({super.key, required this.drawing, required this.painterFor});
  final Drawing drawing;

  /// Pintor de los trazos de una capa.
  final CustomPainter Function(DrawingLayer layer) painterFor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        for (final layer in drawing.layers)
          if (layer.visible) ...[
            CustomPaint(painter: painterFor(layer)),
            if (layer.items.isNotEmpty)
              Opacity(
                opacity: layer.opacity,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (final it in layer.items)
                      PositionedItem(item: it, child: CanvasItemContent(item: it)),
                  ],
                ),
              ),
          ],
      ],
    );
  }
}
