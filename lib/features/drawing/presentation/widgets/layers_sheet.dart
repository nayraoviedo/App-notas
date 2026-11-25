import 'package:flutter/material.dart';

import '../../application/drawing_controller.dart';
import '../../domain/drawing.dart';

/// Panel de capas: la de arriba de la lista es la que queda encima.
/// Tocar = capa activa · ojo = mostrar/ocultar · candado = bloquear ·
/// arrastrar = cambiar orden · deslizador = opacidad.
class LayersSheet extends StatelessWidget {
  const LayersSheet({super.key, required this.controller});
  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final layers = controller.drawing.layers;
        final display = layers.reversed.toList(); // arriba primero
        final activeId = controller.activeLayer.id;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Capas', style: Theme.of(context).textTheme.titleMedium),
                trailing: FilledButton.tonalIcon(
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva'),
                  onPressed: controller.addLayer,
                ),
              ),
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: display.length,
                  onReorder: (oldI, newI) {
                    final ids = display.map((l) => l.id).toList();
                    if (newI > oldI) newI -= 1;
                    ids.insert(newI, ids.removeAt(oldI));
                    controller.reorderLayers(ids.reversed.toList());
                  },
                  itemBuilder: (context, di) {
                    final layer = display[di];
                    final index = layers.length - 1 - di;
                    return _LayerTile(
                      key: ValueKey(layer.id),
                      layer: layer,
                      dragIndex: di,
                      active: layer.id == activeId,
                      canDelete: layers.length > 1,
                      onSelect: () => controller.setActiveLayer(index),
                      onToggleVisible: () => controller.updateLayer(
                          index, (l) => l.copyWith(visible: !l.visible),
                          undoable: false),
                      onToggleLock: () => controller.updateLayer(
                          index, (l) => l.copyWith(locked: !l.locked),
                          undoable: false),
                      onOpacity: (v) => controller.updateLayer(
                          index, (l) => l.copyWith(opacity: v),
                          undoable: false),
                      onAction: (a) => _onAction(context, a, index, layer),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onAction(
      BuildContext context, _LayerAction a, int index, DrawingLayer layer) async {
    switch (a) {
      case _LayerAction.rename:
        final c = TextEditingController(text: layer.name);
        final name = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Nombre de la capa'),
            content: TextField(controller: c, autofocus: true),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, c.text.trim()),
                  child: const Text('Guardar')),
            ],
          ),
        );
        if (name != null && name.isNotEmpty) {
          controller.updateLayer(index, (l) => l.copyWith(name: name));
        }
      case _LayerAction.duplicate:
        controller.duplicateLayer(index);
      case _LayerAction.clear:
        controller.clearLayer(index);
      case _LayerAction.delete:
        controller.deleteLayer(index);
    }
  }
}

enum _LayerAction { rename, duplicate, clear, delete }

class _LayerTile extends StatelessWidget {
  const _LayerTile({
    super.key,
    required this.layer,
    required this.dragIndex,
    required this.active,
    required this.canDelete,
    required this.onSelect,
    required this.onToggleVisible,
    required this.onToggleLock,
    required this.onOpacity,
    required this.onAction,
  });

  final DrawingLayer layer;
  final int dragIndex;
  final bool active;
  final bool canDelete;
  final VoidCallback onSelect;
  final VoidCallback onToggleVisible;
  final VoidCallback onToggleLock;
  final ValueChanged<double> onOpacity;
  final ValueChanged<_LayerAction> onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? scheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Column(
            children: [
              Row(
                children: [
                  ReorderableDragStartListener(
                    index: dragIndex,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${layer.name} · ${layer.strokes.length} trazos',
                      style: TextStyle(fontWeight: active ? FontWeight.w600 : null),
                    ),
                  ),
                  IconButton(
                    tooltip: layer.visible ? 'Ocultar' : 'Mostrar',
                    icon: Icon(layer.visible ? Icons.visibility : Icons.visibility_off),
                    onPressed: onToggleVisible,
                  ),
                  IconButton(
                    tooltip: layer.locked ? 'Desbloquear' : 'Bloquear',
                    icon: Icon(layer.locked ? Icons.lock : Icons.lock_open),
                    onPressed: onToggleLock,
                  ),
                  PopupMenuButton<_LayerAction>(
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: _LayerAction.rename, child: Text('Renombrar')),
                      const PopupMenuItem(value: _LayerAction.duplicate, child: Text('Duplicar')),
                      const PopupMenuItem(value: _LayerAction.clear, child: Text('Vaciar')),
                      PopupMenuItem(
                        value: _LayerAction.delete,
                        enabled: canDelete,
                        child: const Text('Eliminar'),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 48),
                  const Icon(Icons.opacity, size: 18),
                  Expanded(
                    child: Slider(
                      value: layer.opacity,
                      min: 0.05,
                      onChanged: onOpacity,
                    ),
                  ),
                  SizedBox(width: 44, child: Text('${(layer.opacity * 100).round()}%')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
