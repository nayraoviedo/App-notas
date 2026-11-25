import 'package:flutter/material.dart';

import '../../../../core/utils/time_format.dart';
import '../../domain/note_block.dart';

/// Nota escrita mientras se veía un video. Al tocarla, abre el video en ese minuto.
class VideoRefBlockView extends StatelessWidget {
  const VideoRefBlockView({super.key, required this.block, required this.onOpen});

  final VideoRefBlock block;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.movie_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Text(formatMs(block.atMs),
                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(child: Text(block.text)),
            ],
          ),
        ),
      ),
    );
  }
}
