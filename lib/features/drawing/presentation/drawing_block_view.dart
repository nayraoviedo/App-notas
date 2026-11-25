import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../notes/domain/note_block.dart';
import 'painters/drawing_painter.dart';
import 'painters/paper_painter.dart';

/// Miniatura de la hoja dentro de la nota. Al tocarla se abre para editar.
class DrawingBlockView extends ConsumerWidget {
  const DrawingBlockView({super.key, required this.block, required this.onOpen});

  final DrawingBlock block;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drawing = ref.watch(drawingFileProvider(block.path));
    return GestureDetector(
      onTap: onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: drawing.when(
          loading: () => const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => SizedBox(height: 80, child: Center(child: Text('Error: $e'))),
          data: (d) => AspectRatio(
            aspectRatio: d.width / d.height,
            child: FittedBox(
              child: SizedBox(
                width: d.width,
                height: d.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PaperView(paper: d.paper),
                    CustomPaint(painter: StaticDrawingPainter(d)),
                    if (d.bookmarked)
                      const Positioned(
                        top: 0,
                        right: 40,
                        child: Icon(Icons.bookmark, size: 120, color: Color(0xFFE5484D)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
