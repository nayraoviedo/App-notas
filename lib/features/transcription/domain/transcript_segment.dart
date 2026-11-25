/// Un fragmento de transcripción con tiempos en milisegundos.
class TranscriptSegment {
  const TranscriptSegment({
    required this.startMs,
    required this.endMs,
    required this.text,
    this.speakerId,
    this.id,
  });

  /// Id en base de datos (null si aún no se guardó).
  final int? id;
  final int startMs;
  final int endMs;
  final String text;
  final String? speakerId;

  TranscriptSegment copyWith({
    int? startMs,
    int? endMs,
    String? text,
    String? speakerId,
  }) =>
      TranscriptSegment(
        id: id,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        text: text ?? this.text,
        speakerId: speakerId ?? this.speakerId,
      );
}
