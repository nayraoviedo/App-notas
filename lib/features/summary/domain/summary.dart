import 'dart:convert';

class Chapter {
  const Chapter({required this.atMs, required this.title, required this.summary});
  final int atMs;
  final String title;
  final String summary;

  Map<String, Object?> toJson() => {'atMs': atMs, 'title': title, 'summary': summary};
  factory Chapter.fromJson(Map<String, Object?> j) => Chapter(
        atMs: (j['atMs'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
      );
}

class SummaryTask {
  const SummaryTask({required this.task, this.due});
  final String task;
  final String? due;

  Map<String, Object?> toJson() => {'task': task, if (due != null) 'due': due};
  factory SummaryTask.fromJson(Map<String, Object?> j) =>
      SummaryTask(task: j['task'] as String? ?? '', due: j['due'] as String?);
}

/// Resumen completo + por capítulos (cada capítulo con su minuto).
class TranscriptSummary {
  const TranscriptSummary({
    required this.title,
    required this.overview,
    required this.chapters,
    this.keyPoints = const [],
    this.tasks = const [],
    this.provider = '',
  });

  final String title;
  final String overview;
  final List<Chapter> chapters;
  final List<String> keyPoints;
  final List<SummaryTask> tasks;
  final String provider;

  String get chaptersJson => jsonEncode(chapters.map((c) => c.toJson()).toList());
  String get keyPointsJson => jsonEncode(keyPoints);
  String get tasksJson => jsonEncode(tasks.map((t) => t.toJson()).toList());

  static List<Chapter> parseChapters(String json) => [
        for (final c in jsonDecode(json) as List)
          Chapter.fromJson((c as Map).cast<String, Object?>()),
      ];

  static List<String> parseKeyPoints(String json) =>
      (jsonDecode(json) as List).map((e) => '$e').toList();

  static List<SummaryTask> parseTasks(String json) => [
        for (final t in jsonDecode(json) as List)
          SummaryTask.fromJson((t as Map).cast<String, Object?>()),
      ];
}
