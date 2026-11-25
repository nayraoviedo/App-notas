import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/speaker.dart';
import '../domain/voice_embedder.dart';

/// Escucha el audio en vivo y detecta cuándo cambia la voz.
///
/// No decide solo: emite una [SpeakerChangeSuggestion] y espera a que el
/// usuario confirme ("Sí, es Ana" / "Persona nueva") o descarte. Si nadie
/// responde, la grabación sigue sin cortarse.
class SpeakerTracker {
  SpeakerTracker(
    this._embedder, {
    Map<String, List<double>> knownSpeakers = const {},
    this.changeThreshold = 0.55,
    this.matchThreshold = 0.70,
    this.minRms = 0.02,
    this.sampleRate = 16000,
  }) : _known = {...knownSpeakers};

  final VoiceEmbedder _embedder;
  final Map<String, List<double>> _known;

  /// Similitud por debajo de la cual se considera "otra voz".
  final double changeThreshold;

  /// Similitud por encima de la cual se reconoce a alguien conocido.
  final double matchThreshold;

  /// Energía mínima para considerar que hay voz (no silencio).
  final double minRms;
  final int sampleRate;

  final _suggestions = StreamController<SpeakerChangeSuggestion>.broadcast();
  Stream<SpeakerChangeSuggestion> get suggestions => _suggestions.stream;

  final List<SpeakerTurn> _turns = [];
  List<SpeakerTurn> get turns => List.unmodifiable(_turns);

  String? _currentSpeakerId;
  List<double>? _currentVoice;
  SpeakerChangeSuggestion? _pending;
  int _consecutiveDifferent = 0;

  final List<double> _buffer = [];
  int _samplesSeen = 0;
  int? _carryByte;
  bool _busy = false;

  /// El usuario indica a mano quién habla desde [atMs] (funciona aunque no
  /// haya modelo de voz). Con atMs = 0 es "quién empieza hablando".
  void markTurn(String speakerId, int atMs) {
    _pending = null;
    _consecutiveDifferent = 0;
    _currentSpeakerId = speakerId;
    _currentVoice = _known[speakerId];
    _turns
      ..removeWhere((t) => t.atMs == atMs)
      ..add(SpeakerTurn(atMs: atMs, speakerId: speakerId))
      ..sort((a, b) => a.atMs.compareTo(b.atMs));
  }

  /// Recibe audio PCM16 little-endian mono, tal como lo entrega `record`.
  void addPcm16(Uint8List bytes) {
    if (!_embedder.isAvailable) return;
    var i = 0;
    if (_carryByte != null && bytes.isNotEmpty) {
      _pushSample(_carryByte! | (bytes[0] << 8));
      _carryByte = null;
      i = 1;
    }
    for (; i + 1 < bytes.length; i += 2) {
      _pushSample(bytes[i] | (bytes[i + 1] << 8));
    }
    if (i < bytes.length) _carryByte = bytes[i];
  }

  void _pushSample(int raw) {
    final signed = raw >= 0x8000 ? raw - 0x10000 : raw;
    _buffer.add(signed / 32768.0);
    _samplesSeen++;
    if (_buffer.length >= _embedder.windowSamples) {
      final window = Float32List.fromList(_buffer);
      _buffer.clear();
      final windowStartMs =
          ((_samplesSeen - window.length) * 1000 / sampleRate).round();
      unawaited(_analyze(window, windowStartMs));
    }
  }

  Future<void> _analyze(Float32List window, int atMs) async {
    if (_busy || _pending != null) return; // no saturar ni preguntar dos veces
    if (rms(window) < minRms) return; // silencio
    _busy = true;
    try {
      final emb = await _embedder.embed(window);
      if (emb == null) return;

      if (_currentVoice == null) {
        _currentVoice = emb;
        return;
      }
      final sim = cosineSimilarity(emb, _currentVoice!);
      if (sim >= changeThreshold) {
        _consecutiveDifferent = 0;
        _currentVoice = blend(_currentVoice!, emb);
        return;
      }
      // Pedimos dos ventanas seguidas distintas para evitar falsas alarmas.
      _consecutiveDifferent++;
      if (_consecutiveDifferent < 2) return;
      _consecutiveDifferent = 0;

      _pending = SpeakerChangeSuggestion(
        atMs: atMs,
        embedding: emb,
        likelySpeakerId: bestMatch(emb),
      );
      _suggestions.add(_pending!);
    } finally {
      _busy = false;
    }
  }

  /// Devuelve el id de la persona conocida más parecida, si supera el umbral.
  String? bestMatch(List<double> emb) {
    String? best;
    var bestSim = matchThreshold;
    _known.forEach((id, voice) {
      if (id == _currentSpeakerId) return;
      final s = cosineSimilarity(emb, voice);
      if (s >= bestSim) {
        bestSim = s;
        best = id;
      }
    });
    return best;
  }

  /// El usuario confirmó que ahora habla [speakerId] (nuevo o conocido).
  /// Devuelve la huella actualizada para guardarla en la base de datos.
  List<double>? confirm(String speakerId) {
    final s = _pending;
    if (s == null) return null;
    _pending = null;
    final updated = _known[speakerId] == null
        ? s.embedding
        : blend(_known[speakerId]!, s.embedding);
    _known[speakerId] = updated;
    _currentSpeakerId = speakerId;
    _currentVoice = s.embedding;
    _turns.add(SpeakerTurn(atMs: s.atMs, speakerId: speakerId));
    return updated;
  }

  /// El usuario dijo "No, sigue la misma persona".
  void dismiss() {
    final s = _pending;
    _pending = null;
    if (s != null && _currentVoice != null) {
      _currentVoice = blend(_currentVoice!, s.embedding);
    }
  }

  Future<void> dispose() => _suggestions.close();

  // ------------------------------------------------------------ Utilidades

  static double rms(Float32List x) {
    if (x.isEmpty) return 0;
    var sum = 0.0;
    for (final v in x) {
      sum += v * v;
    }
    return math.sqrt(sum / x.length);
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  /// Media móvil: la huella se va ajustando con cada trozo nuevo.
  static List<double> blend(List<double> current, List<double> next,
      {double weight = 0.2}) {
    final n = math.min(current.length, next.length);
    return List<double>.generate(
        n, (i) => current[i] * (1 - weight) + next[i] * weight);
  }
}
