import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/utils/time_format.dart';
import '../../domain/note_block.dart';

class ImageBlockView extends StatelessWidget {
  const ImageBlockView({super.key, required this.block, this.onOpenVideo});

  final ImageBlock block;

  /// Para capturas de video: abre el video en el minuto de la captura.
  final void Function(String videoPath, int atMs)? onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final anchor = block.anchor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onTap: () => _openFullScreen(context),
            child: Image.file(File(block.path), fit: BoxFit.cover),
          ),
        ),
        if (anchor != null && anchor.isVideo)
          TextButton.icon(
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: Text('Captura del video · ${formatMs(anchor.atMs)}'),
            onPressed: () => onOpenVideo?.call(anchor.videoPath!, anchor.atMs),
          ),
      ],
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: InteractiveViewer(child: Image.file(File(block.path))),
        ),
      ),
    ));
  }
}
