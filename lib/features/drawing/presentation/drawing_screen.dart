import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../application/drawing_controller.dart';
import '../domain/drawing.dart';
import 'painters/drawing_painter.dart';
import 'painters/paper_painter.dart';
import 'widgets/layers_sheet.dart';
import 'widgets/paper_sheet.dart';
import 'widgets/tool_settings_sheet.dart';

/// Hoja para escribir a mano y dibujar, con capas.
class DrawingScreen extends ConsumerStatefulWidget {
  const DrawingScreen({super.key, required this.path});

  /// Archivo JSON de la hoja.
  final String path;

  @override
  ConsumerState<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends ConsumerState<DrawingScreen> {
  DrawingController? _ctl;
  final _transform = TransformationController();
  double? _fittedWidth;

  final _pointers = <int>{};
  int? _drawingPointer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(drawingStoreProvider);
    final drawing = await store.load(widget.path);
    if (!mounted) return;
    setState(() {
      _ctl = DrawingController(drawing, onSave: (d) => store.save(widget.path, d));
    });
  }

  @override
  void dispose() {
    _ctl?.flush();
    _ctl?.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _ctl?.flush();
    ref.invalidate(drawingFileProvider(widget.path)); // refrescar la vista previa
    if (mounted) Navigator.of(context).pop();
  }

  // ------------------------------------------------------------------ Entrada

  bool _accepts(PointerEvent e) {
    final ctl = _ctl!;
    if (ctl.mode == InputMode.pan) return false;
    if (ctl.stylusOnly && e.kind != PointerDeviceKind.stylus) return false;
    return true;
  }

  double? _pressure(PointerEvent e) => DrawingController.normalizePressure(
        isStylus: e.kind == PointerDeviceKind.stylus,
        pressure: e.pressure,
        min: e.pressureMin,
        max: e.pressureMax,
      );

  void _onDown(PointerDownEvent e) {
    final ctl = _ctl!;
    _pointers.add(e.pointer);
    if (_pointers.length > 1) {
      // Segundo dedo: es un gesto de zoom, no un trazo.
      ctl.cancelStroke();
      _drawingPointer = null;
      return;
    }
    if (!_accepts(e)) return;
    if (!ctl.canDrawOnActiveLayer) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('La capa activa está oculta o bloqueada')));
      return;
    }
    _drawingPointer = e.pointer;
    if (ctl.mode == InputMode.eraseStrokes) {
      ctl.beginEraseStrokes();
      ctl.eraseStrokesAt(e.localPosition);
    } else {
      ctl.startStroke(e.localPosition, _pressure(e));
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _drawingPointer) return;
    final ctl = _ctl!;
    if (ctl.mode == InputMode.eraseStrokes) {
      ctl.eraseStrokesAt(e.localPosition);
    } else {
      ctl.extendStroke(e.localPosition, _pressure(e));
    }
  }

  void _onUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    if (e.pointer != _drawingPointer) return;
    _drawingPointer = null;
    _ctl!.endStroke();
  }

  void _onCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (e.pointer == _drawingPointer) {
      _drawingPointer = null;
      _ctl!.cancelStroke();
    }
  }

  // ---------------------------------------------------------------- Interfaz

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        appBar: AppBar(
          leading: BackButton(onPressed: _close),
          title: const Text('Hoja'),
          actions: ctl == null
              ? null
              : [
                  ListenableBuilder(
                    listenable: ctl,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Deshacer',
                          icon: const Icon(Icons.undo),
                          onPressed: ctl.canUndo ? ctl.undo : null,
                        ),
                        IconButton(
                          tooltip: 'Rehacer',
                          icon: const Icon(Icons.redo),
                          onPressed: ctl.canRedo ? ctl.redo : null,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Capas',
                    icon: const Icon(Icons.layers_outlined),
                    onPressed: () => _sheet(LayersSheet(controller: ctl)),
                  ),
                  IconButton(
                    tooltip: 'Hoja',
                    icon: const Icon(Icons.description_outlined),
                    onPressed: () => _sheet(PaperSheet(
                      controller: ctl,
                      onPickImage: ref.read(cameraServiceProvider).pickImageFromGallery,
                    )),
                  ),
                ],
        ),
        body: ctl == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(child: _canvas(ctl)),
                  _ToolBar(controller: ctl, onOpenSettings: () => _sheet(ToolSettingsSheet(controller: ctl))),
                ],
              ),
      ),
    );
  }

  Widget _canvas(DrawingController ctl) {
    return LayoutBuilder(
      builder: (context, c) {
        return ListenableBuilder(
          listenable: ctl,
          builder: (context, _) {
            final d = ctl.drawing;
            // Ajustar la hoja al ancho de la pantalla la primera vez (y al
            // girarla entre vertical/horizontal).
            final fitKey = c.maxWidth * 10000 + d.width;
            if (_fittedWidth != fitKey) {
              _fittedWidth = fitKey;
              final scale = (c.maxWidth - 16) / d.width;
              _transform.value = Matrix4.identity()
                ..setEntry(0, 0, scale)
                ..setEntry(1, 1, scale)
                ..setEntry(0, 3, 8)
                ..setEntry(1, 3, 8);
            }
            return InteractiveViewer(
              transformationController: _transform,
              constrained: false,
              minScale: 0.2,
              maxScale: 8,
              boundaryMargin: const EdgeInsets.all(400),
              panEnabled: ctl.mode == InputMode.pan || ctl.stylusOnly,
              child: Container(
                width: d.width,
                height: d.height,
                decoration: const BoxDecoration(
                  boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black26)],
                ),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onDown,
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  onPointerCancel: _onCancel,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: PaperView(paper: d.paper),
                      ),
                      RepaintBoundary(
                        child: CustomPaint(painter: DrawingPainter(ctl)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _sheet(Widget child) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: child,
        ),
      );
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.controller, required this.onOpenSettings});
  final DrawingController controller;
  final VoidCallback onOpenSettings;

  static const _icons = {
    ToolType.pen: Icons.edit,
    ToolType.pencil: Icons.create_outlined,
    ToolType.brush: Icons.brush,
    ToolType.marker: Icons.border_color,
    ToolType.highlighter: Icons.highlight,
    ToolType.eraser: Icons.auto_fix_normal,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final c = controller;
        Widget button({
          required IconData icon,
          required String tooltip,
          required bool selected,
          required VoidCallback onTap,
          Color? dot,
        }) =>
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  IconButton(
                    tooltip: tooltip,
                    isSelected: selected,
                    style: IconButton.styleFrom(
                      backgroundColor: selected ? scheme.primaryContainer : null,
                    ),
                    icon: Icon(icon),
                    onPressed: onTap,
                  ),
                  if (dot != null)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                ],
              ),
            );

        return Material(
          elevation: 8,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  for (final t in ToolType.values)
                    button(
                      icon: _icons[t]!,
                      tooltip: t.label,
                      selected: c.mode == InputMode.draw && c.tool == t,
                      dot: t == ToolType.eraser ? null : Color(c.settingsFor(t).color),
                      onTap: () {
                        // Tocar la herramienta ya elegida abre color y grosor.
                        if (c.mode == InputMode.draw && c.tool == t) {
                          onOpenSettings();
                        } else {
                          c.selectTool(t);
                        }
                      },
                    ),
                  const SizedBox(height: 32, child: VerticalDivider()),
                  button(
                    icon: Icons.cleaning_services_outlined,
                    tooltip: 'Borrar trazos completos',
                    selected: c.mode == InputMode.eraseStrokes,
                    onTap: () => c.selectMode(InputMode.eraseStrokes),
                  ),
                  button(
                    icon: Icons.pan_tool_outlined,
                    tooltip: 'Mover la hoja',
                    selected: c.mode == InputMode.pan,
                    onTap: () => c.selectMode(InputMode.pan),
                  ),
                  button(
                    icon: Icons.tune,
                    tooltip: 'Color y grosor',
                    selected: false,
                    onTap: onOpenSettings,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
