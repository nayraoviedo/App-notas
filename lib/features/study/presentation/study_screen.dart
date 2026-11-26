import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/daily_stats.dart';
import '../../../core/providers.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/cat_mascot.dart';
import '../../notes/domain/note.dart';
import '../../settings/settings.dart';
import '../../summary/data/llm_clients.dart';
import '../domain/flashcard.dart';
import '../../../core/widgets/study_timer.dart';

/// Modelos de IA con clave guardada, en el orden de preferencia.
Future<List<LlmClient>> availableLlms(WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final keys = ref.read(apiKeysProvider);
  final order = [settings.aiProvider, ...AiProvider.values.where((p) => p != settings.aiProvider)];
  return [
    for (final p in order)
      if ((await keys.read(p)) case final key? when key.isNotEmpty)
        switch (p) {
          AiProvider.gemini => GeminiClient(apiKey: key, model: settings.geminiModel),
          AiProvider.groq => GroqClient(apiKey: key, model: settings.groqModel),
        },
  ];
}

/// Crear una tarjeta (también se usa desde las notas de texto).
Future<void> showNewFlashcard(BuildContext context, WidgetRef ref, {String back = '', String? noteId}) async {
  final front = TextEditingController();
  final backCtl = TextEditingController(text: back);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nueva tarjeta de repaso'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: front,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Pregunta (frente)'),
          ),
          TextField(
            controller: backCtl,
            maxLines: 5,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Respuesta (reverso)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
      ],
    ),
  );
  if (ok != true || front.text.trim().isEmpty) return;
  await ref
      .read(flashcardsRepositoryProvider)
      .add(front: front.text.trim(), back: backCtl.text.trim(), noteId: noteId);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Tarjeta guardada en "Estudio" ✓')));
  }
}

/// Estudio: repasar tarjetas, verlas todas y preguntarle a tus notas.
class StudyScreen extends ConsumerWidget {
  const StudyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(flashcardsProvider).valueOrNull ?? const <Flashcard>[];
    final due = cards.where((c) => !c.due.isAfter(DateTime.now())).toList();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estudio'),
          actions: [
            const StudyTimerButton(),
            IconButton(
              tooltip: 'Modo examen',
              icon: const Icon(Icons.quiz_outlined),
              onPressed: () => context.push('/exam'),
            ),
            IconButton(
              tooltip: 'Horario y pendientes',
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () => context.push('/planner'),
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: 'Repasar (${due.length})'),
            Tab(text: 'Tarjetas (${cards.length})'),
            const Tab(text: 'Pregúntale'),
          ]),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Nueva tarjeta',
          onPressed: () => showNewFlashcard(context, ref),
          child: const Icon(Icons.add),
        ),
        body: TabBarView(children: [
          _Review(due: due),
          _CardList(cards: cards),
          const _AskNotes(),
        ]),
      ),
    );
  }
}

class _Review extends ConsumerStatefulWidget {
  const _Review({required this.due});
  final List<Flashcard> due;

  @override
  ConsumerState<_Review> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<_Review> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    if (widget.due.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CatMascot(kind: CatKind.gray, size: 100),
              SizedBox(height: 12),
              Text('¡Nada que repasar por ahora! 🎉\nCrea tarjetas con el botón + o desde tus notas de texto.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    final c = widget.due.first;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // Abajo deja lugar para el botón + (no tapa "Fácil").
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 92),
      child: Column(
        children: [
          Text('Quedan ${widget.due.length}', style: const TextStyle(color: Colors.black45)),
          const SizedBox(height: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _show = true),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Text(c.front,
                              textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                          if (_show) ...[
                            const Divider(height: 40),
                            Text(c.back.isEmpty ? '(sin respuesta)' : c.back,
                                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Text('Toca para ver la respuesta',
                                  style: TextStyle(color: scheme.primary)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_show)
            Row(
              children: [
                for (final r in Recall.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: switch (r) {
                            Recall.again => const Color(0xFFFFCDD2),
                            Recall.hard => const Color(0xFFFFE0B2),
                            Recall.good => const Color(0xFFC8E6C9),
                            Recall.easy => const Color(0xFFBBDEFB),
                          },
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () async {
                          await ref.read(flashcardsRepositoryProvider).save(schedule(c, r));
                          await DailyStats.bump(ref.read(sharedPreferencesProvider), 'reviews');
                          if (mounted) setState(() => _show = false);
                        },
                        child: Column(
                          children: [
                            Text(r.label, style: const TextStyle(fontSize: 13)),
                            Text(nextLabel(c, r), style: const TextStyle(fontSize: 10.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CardList extends ConsumerWidget {
  const _CardList({required this.cards});
  final List<Flashcard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cards.isEmpty) {
      return const Center(child: Text('Todavía no hay tarjetas.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: cards.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = cards[i];
        final d = c.due;
        return Dismissible(
          key: ValueKey(c.id),
          direction: DismissDirection.endToStart,
          background: Container(color: Colors.red.shade100, alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete_outline)),
          onDismissed: (_) => ref.read(flashcardsRepositoryProvider).delete(c.id),
          child: ListTile(
            title: Text(c.front, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(c.back, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text('${d.day}/${d.month}', style: const TextStyle(color: Colors.black45)),
          ),
        );
      },
    );
  }
}

/// "Pregúntale a tus notas": busca en textos y transcripciones y la IA
/// responde citando de dónde sacó la respuesta.
class _AskNotes extends ConsumerStatefulWidget {
  const _AskNotes();

  @override
  ConsumerState<_AskNotes> createState() => _AskNotesState();
}

class _AskNotesState extends ConsumerState<_AskNotes> {
  final _q = TextEditingController();
  bool _busy = false;
  String? _answer;
  String? _error;
  List<SearchHit> _sources = const [];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final question = _q.text.trim();
    if (question.isEmpty) return;
    setState(() {
      _busy = true;
      _answer = null;
      _error = null;
      _sources = const [];
    });
    try {
      // 1) Buscar fragmentos relacionados (palabras de 4+ letras).
      final repo = ref.read(notesRepositoryProvider);
      final words = question
          .toLowerCase()
          .split(RegExp(r'[^a-záéíóúñü0-9]+'))
          .where((w) => w.length >= 4)
          .toSet();
      final hits = <String, (SearchHit, int)>{};
      for (final w in words) {
        for (final h in await repo.search(w)) {
          final key = '${h.blockId}-${h.atMs}-${h.snippet.hashCode}';
          final prev = hits[key];
          hits[key] = (h, (prev?.$2 ?? 0) + 1);
        }
      }
      final ranked = hits.values.toList()..sort((a, b) => b.$2.compareTo(a.$2));
      final top = [for (final (h, _) in ranked.take(25)) h];
      if (top.isEmpty) {
        setState(() {
          _busy = false;
          _answer = 'No encontré nada en tus notas sobre eso. Prueba con otras palabras.';
        });
        return;
      }
      // 2) Preguntarle a la IA solo con esos fragmentos.
      final llms = await availableLlms(ref);
      if (llms.isEmpty) {
        setState(() {
          _busy = false;
          _sources = top.take(8).toList();
          _answer = 'Para que te responda con IA, pon una clave gratis de Groq o Gemini en Ajustes. '
              'Mientras tanto, estos son los fragmentos de tus notas que hablan de eso:';
        });
        return;
      }
      final excerpts = [
        for (var i = 0; i < top.length; i++)
          '[$i] (${top[i].noteTitle.isEmpty ? 'Nota' : top[i].noteTitle}'
              '${top[i].atMs != null ? ', minuto ${formatMs(top[i].atMs!)}' : ''}): ${_clip(top[i].snippet)}',
      ].join('\n');
      const system = 'Eres un asistente de estudio. Responde en español, claro y breve, usando SOLO '
          'los fragmentos de las notas del usuario. Si no está en las notas, dilo. Devuelve JSON: '
          '{"answer": "texto", "sources": [números de los fragmentos usados]}';
      final user = 'Pregunta: $question\n\nFragmentos de mis notas:\n$excerpts';
      Object? lastError;
      for (final llm in llms) {
        try {
          final raw = await llm.completeJson(system: system, user: user);
          final json = jsonDecode(raw) as Map<String, Object?>;
          final idx = [for (final v in (json['sources'] as List? ?? const [])) if (v is int && v < top.length) v];
          setState(() {
            _answer = json['answer'] as String? ?? raw;
            _sources = [for (final i in idx) top[i]];
            _busy = false;
          });
          return;
        } catch (e) {
          lastError = e;
        }
      }
      throw lastError ?? 'Sin respuesta';
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'No se pudo responder: $e';
      });
    }
  }

  static String _clip(String s) => s.length > 500 ? '${s.substring(0, 500)}…' : s;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        TextField(
          controller: _q,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: '¿Qué dijo el profe sobre la mitosis?',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _busy ? null : _ask),
          ),
          onSubmitted: (_) => _ask(),
        ),
        const SizedBox(height: 16),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_answer != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CatMascot(kind: CatKind.orange, size: 40),
                  const SizedBox(width: 12),
                  Expanded(child: SelectableText(_answer!)),
                ],
              ),
            ),
          ),
        for (final h in _sources)
          ListTile(
            leading: Icon(h.atMs != null ? Icons.graphic_eq : Icons.notes),
            title: Text(h.noteTitle.isEmpty ? 'Nota sin título' : h.noteTitle),
            subtitle: Text(
              '${h.atMs != null ? '${formatMs(h.atMs!)} · ' : ''}${_clip(h.snippet)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => context.push(h.atMs != null && h.blockId != null
                ? '/notes/${h.noteId}/audio/${h.blockId}'
                : '/notes/${h.noteId}'),
          ),
      ],
    );
  }
}
