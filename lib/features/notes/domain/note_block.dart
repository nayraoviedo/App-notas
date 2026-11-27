import 'dart:convert';

/// Marca en una grabación: "⭐ Importante" (sin [label]) o nota rápida.
class AudioMarker {
  const AudioMarker({required this.atMs, this.label, this.id});
  final int? id;
  final int atMs;
  final String? label;

  bool get isQuickNote => label != null && label!.trim().isNotEmpty;
}

/// Ancla un bloque a un momento de un audio o de un video.
class MediaAnchor {
  const MediaAnchor.audio({required String this.audioBlockId, required this.atMs})
      : videoPath = null;

  const MediaAnchor.video({required String this.videoPath, required this.atMs})
      : audioBlockId = null;

  final String? audioBlockId;
  final String? videoPath;
  final int atMs;

  bool get isAudio => audioBlockId != null;
  bool get isVideo => videoPath != null;
}

/// Una nota está hecha de bloques. Así una misma nota mezcla texto,
/// grabaciones con transcripción, fotos y referencias a videos.
sealed class NoteBlock {
  const NoteBlock({required this.id, required this.position});

  final String id;
  final int position;
}

class TextBlock extends NoteBlock {
  const TextBlock({
    required super.id,
    required super.position,
    required this.text,
    this.fontFamily,
    this.fontSize,
    this.marks = const [],
    this.textColor,
  });

  final String text;

  /// Partes resaltadas (como con un resaltador).
  final List<TextMark> marks;

  /// Color de la letra (null = el del tema).
  final int? textColor;

  /// null = fuente del sistema.
  final String? fontFamily;
  final double? fontSize;
}

class AudioBlock extends NoteBlock {
  const AudioBlock({
    required super.id,
    required super.position,
    required this.path,
    required this.durationMs,
  });

  final String path;
  final int durationMs;
}

class ImageBlock extends NoteBlock {
  const ImageBlock({
    required super.id,
    required super.position,
    required this.path,
    this.anchor,
  });

  final String path;

  /// Si la foto se tomó durante una grabación o es una captura de video.
  final MediaAnchor? anchor;
}

/// Hoja para escribir a mano o dibujar (con capas). Los trazos viven en un
/// archivo JSON aparte.
class DrawingBlock extends NoteBlock {
  const DrawingBlock({required super.id, required super.position, required this.path});

  final String path;
}

/// Una nota escrita mientras se veía un video, con el minuto exacto.
class VideoRefBlock extends NoteBlock {
  const VideoRefBlock({
    required super.id,
    required super.position,
    required this.videoPath,
    required this.atMs,
    required this.text,
  });

  final String videoPath;
  final int atMs;
  final String text;
}

/// Un tramo resaltado del texto: [start, end) con un color.
class TextMark {
  const TextMark(this.start, this.end, this.color);
  final int start;
  final int end;
  final int color;

  static List<TextMark> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final m in jsonDecode(raw) as List)
          TextMark((m as List)[0] as int, m[1] as int, m[2] as int),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<TextMark> marks) =>
      jsonEncode([for (final m in marks) [m.start, m.end, m.color]]);
}
