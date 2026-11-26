import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/daily_stats.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/cat_mascot.dart';
import '../../settings/settings.dart';
import '../domain/flashcard.dart';

/// Una pregunta del examen: la tarjeta y 4 respuestas (una correcta).
class ExamQuestion {
  const ExamQuestion(this.card, this.options, this.correct);
  final Flashcard card;
  final List<String> options;
  final int correct;
}

/// Arma un examen de opción múltiple con las tarjetas: las respuestas
/// incorrectas salen de otras tarjetas.
List<ExamQuestion> buildExam(List<Flashcard> cards, {int count = 10, math.Random? random}) {
  final rnd = random ?? math.Random();
  final usable = cards.where((c) => c.back.trim().isNotEmpty).toList();
  final backs = {for (final c in usable) c.back.trim()}.toList();
  if (usable.length < 2 || backs.length < 2) return const [];
  // Primero las que tocan repasar, luego al azar.
  usable.shuffle(rnd);
  usable.sort((a, b) => a.due.compareTo(b.due));
  return [
    for (final c in usable.take(count))
      () {
        final wrong = (backs.where((b) => b != c.back.trim()).toList()..shuffle(rnd)).take(3);
        final opts = [c.back.trim(), ...wrong]..shuffle(rnd);
        return ExamQuestion(c, opts, opts.indexOf(c.back.trim()));
      }(),
  ];
}

class ExamScreen extends ConsumerStatefulWidget {
  const ExamScreen({super.key, this.seed});
  final int? seed;

  @override
  ConsumerState<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends ConsumerState<ExamScreen> {
  List<ExamQuestion>? _qs;
  int _i = 0;
  int? _picked;
  int _score = 0;

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(flashcardsProvider).valueOrNull;
    if (cards != null && _qs == null) {
      _qs = buildExam(cards, random: widget.seed == null ? null : math.Random(widget.seed));
    }
    final qs = _qs;
    return Scaffold(
      appBar: AppBar(title: const Text('Modo examen')),
      body: qs == null
          ? const Center(child: CircularProgressIndicator())
          : qs.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Necesitas al menos 2 tarjetas con respuesta para hacer un examen.',
                        textAlign: TextAlign.center),
                  ),
                )
              : _i >= qs.length
                  ? _result(qs.length)
                  : _question(qs[_i], qs.length),
    );
  }

  Widget _question(ExamQuestion q, int total) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        LinearProgressIndicator(value: (_i + 1) / total, minHeight: 6, borderRadius: BorderRadius.circular(3)),
        const SizedBox(height: 8),
        Text('Pregunta ${_i + 1} de $total · ✓ $_score', style: const TextStyle(color: Colors.black45)),
        const SizedBox(height: 16),
        Text(q.card.front, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        for (final (k, o) in q.options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: _picked == null
                  ? scheme.surfaceContainerHighest
                  : k == q.correct
                      ? const Color(0xFFC8E6C9)
                      : k == _picked
                          ? const Color(0xFFFFCDD2)
                          : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _picked != null ? null : () => _answer(q, k),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 13, child: Text('ABCD'[k], style: const TextStyle(fontSize: 12))),
                      const SizedBox(width: 12),
                      Expanded(child: Text(o)),
                      if (_picked != null && k == q.correct) const Icon(Icons.check_circle, color: Colors.green),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_picked != null)
          FilledButton(
            onPressed: () => setState(() {
              _i++;
              _picked = null;
            }),
            child: Text(_i + 1 < total ? 'Siguiente' : 'Ver resultado'),
          ),
      ],
    );
  }

  Future<void> _answer(ExamQuestion q, int k) async {
    final ok = k == q.correct;
    setState(() {
      _picked = k;
      if (ok) _score++;
    });
    // Lo que fallas vuelve pronto al repaso; lo que aciertas se aleja.
    await ref.read(flashcardsRepositoryProvider).save(schedule(q.card, ok ? Recall.good : Recall.again));
    await DailyStats.bump(ref.read(sharedPreferencesProvider), 'reviews');
  }

  Widget _result(int total) {
    final pct = (_score * 100 / total).round();
    final msg = pct >= 90
        ? '¡Perfecto! Estás lista 🎉'
        : pct >= 70
            ? '¡Muy bien! Repasa las que fallaste.'
            : pct >= 50
                ? 'Vas bien, un repaso más y sale.'
                : 'Tranqui, repasa y vuelve a intentarlo 💪';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CatMascot(kind: pct >= 70 ? CatKind.orange : CatKind.gray, size: 110),
            const SizedBox(height: 16),
            Text('$_score / $total', style: Theme.of(context).textTheme.displaySmall),
            Text('$pct %', style: const TextStyle(color: Colors.black45)),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => setState(() {
                _qs = null;
                _i = 0;
                _score = 0;
                _picked = null;
              }),
              icon: const Icon(Icons.refresh),
              label: const Text('Otro examen'),
            ),
          ],
        ),
      ),
    );
  }
}
