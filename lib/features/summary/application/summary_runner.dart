import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../settings/settings.dart';
import '../data/llm_clients.dart';
import '../domain/summary.dart';
import 'summary_service.dart';

/// Resumen guardado de una grabación (null si aún no se generó).
final summaryProvider = StreamProvider.family<TranscriptSummary?, String>((ref, blockId) =>
    ref.watch(notesRepositoryProvider).watchSummary(blockId).map((row) => row == null
        ? null
        : TranscriptSummary(
            title: row.title,
            overview: row.overview,
            chapters: TranscriptSummary.parseChapters(row.chaptersJson),
            keyPoints: TranscriptSummary.parseKeyPoints(row.keyPointsJson),
            tasks: TranscriptSummary.parseTasks(row.tasksJson),
            provider: row.provider,
          )));

/// Genera el resumen con el servicio elegido en Ajustes (y el otro de
/// respaldo, si tiene clave) y lo guarda en la base de datos.
Future<void> generateSummary(
  WidgetRef ref,
  String blockId, {
  void Function(String status)? onStatus,
}) async {
  final settings = ref.read(settingsProvider);
  final keys = ref.read(apiKeysProvider);
  final order = [
    settings.aiProvider,
    ...AiProvider.values.where((p) => p != settings.aiProvider),
  ];
  final clients = <LlmClient>[];
  for (final p in order) {
    final key = await keys.read(p);
    if (key == null || key.isEmpty) continue;
    clients.add(switch (p) {
      AiProvider.gemini => GeminiClient(apiKey: key, model: settings.geminiModel),
      AiProvider.groq => GroqClient(apiKey: key, model: settings.groqModel),
    });
  }

  final segments = await ref.read(segmentsProvider(blockId).future);
  final markers = await ref.read(markersProvider(blockId).future);
  final speakers = await ref.read(speakersProvider.future);

  final summary = await SummaryService(clients, language: settings.language).summarize(
    segments: segments,
    markers: markers,
    speakerNames: {for (final s in speakers) s.id: s.name},
    onStatus: onStatus,
  );

  await ref.read(notesRepositoryProvider).saveSummary(SummariesCompanion.insert(
        blockId: blockId,
        title: summary.title,
        overview: summary.overview,
        chaptersJson: summary.chaptersJson,
        keyPointsJson: Value(summary.keyPointsJson),
        tasksJson: Value(summary.tasksJson),
        provider: summary.provider,
        createdAt: DateTime.now(),
      ));
}
