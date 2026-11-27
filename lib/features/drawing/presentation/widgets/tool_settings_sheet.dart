import 'package:flutter/material.dart';

import '../../application/drawing_controller.dart';
import '../../domain/drawing.dart';
import '../painters/stroke_renderer.dart';

const drawingPalette = <int>[
  0xFF1F2328, 0xFF5C6370, 0xFFFFFFFF, 0xFFE5484D, 0xFFFF8A3D, 0xFFFFD60A,
  0xFF30A46C, 0xFF12A594, 0xFF1677FF, 0xFF6E56CF, 0xFFD6409F, 0xFF8D6E63,
];

/// Color y grosor de la herramienta actual, con vista previa del trazo.
class ToolSettingsSheet extends StatelessWidget {
  const ToolSettingsSheet({super.key, required this.controller});
  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tool = controller.tool;
        final s = controller.settings;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tool.label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: CustomPaint(
                    painter: _PreviewPainter(tool, s),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Grosor'),
                    Expanded(
                      child: Slider(
                        min: 1,
                        max: tool == ToolType.eraser || tool == ToolType.highlighter ? 80 : 40,
                        value: s.size.clamp(1, 80),
                        onChanged: controller.setSize,
                      ),
                    ),
                    SizedBox(width: 32, child: Text(s.size.round().toString())),
                  ],
                ),
                if (tool != ToolType.eraser) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final c in drawingPalette)
                        GestureDetector(
                          onTap: () => controller.setColor(c),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: c == s.color ? 3 : 1,
                                color: c == s.color
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.black26,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Solo lápiz óptico'),
                  subtitle: const Text('El dedo mueve la hoja y el lápiz escribe'),
                  value: controller.stylusOnly,
                  onChanged: (_) => controller.toggleStylusOnly(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.tool, this.settings);
  final ToolType tool;
  final ToolSettings settings;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <StrokePoint>[];
    for (var i = 0; i <= 40; i++) {
      final t = i / 40;
      final x = 24 + t * (size.width - 48);
      final y = size.height / 2 + 14 * (t < 0.5 ? (t * 4 - 1) : (3 - t * 4)).clamp(-1, 1);
      pts.add(StrokePoint(x, y, 0.3 + 0.7 * (1 - (t - 0.5).abs() * 2)));
    }
    final stroke = Stroke(
      tool: tool == ToolType.eraser ? ToolType.marker : tool,
      color: tool == ToolType.eraser ? 0xFFBDBDBD : settings.color,
      size: settings.size,
      points: pts,
    );
    StrokeRenderer.paint(canvas, stroke);
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.tool != tool || old.settings.color != settings.color || old.settings.size != settings.size;
}
