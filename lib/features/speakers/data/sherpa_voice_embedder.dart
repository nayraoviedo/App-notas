import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../domain/voice_embedder.dart';

/// Huella de voz con sherpa-onnx, 100 % en el teléfono.
///
/// - El modelo (~25–40 MB) se descarga una sola vez y queda guardado.
/// - El cálculo corre en un isolate aparte para no trabar la pantalla.
/// - Mientras el modelo no esté listo, [isAvailable] es false y la app
///   simplemente no sugiere cambios de voz (se puede marcar a mano).
///
/// Otros modelos compatibles (inglés, multilenguaje) están en:
/// https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models
class SherpaVoiceEmbedder implements VoiceEmbedder {
  SherpaVoiceEmbedder({
    this.modelUrl = defaultModelUrl,
    this.windowSamples = 24000,
  });

  static const defaultModelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'speaker-recongition-models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';

  final String modelUrl;

  @override
  final int windowSamples;

  SendPort? _worker;
  Isolate? _isolate;
  ReceivePort? _fromWorker;
  Future<void>? _preparing;
  final _pending = <int, Completer<List<double>?>>{};
  int _nextId = 0;

  @override
  bool get isAvailable => _worker != null;

  /// Descarga el modelo si hace falta y arranca el isolate. Se puede llamar
  /// varias veces; solo prepara una vez.
  @override
  Future<void> prepare() => _preparing ??= _prepare().catchError((Object e) {
        _preparing = null; // permitir reintentar la próxima vez
        throw e;
      });

  Future<void> _prepare() async {
    final modelPath = await _ensureModel();
    final fromWorker = ReceivePort();
    _fromWorker = fromWorker;
    final ready = Completer<SendPort>();

    fromWorker.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else if (msg is List && msg.length == 2) {
        final id = msg[0] as int;
        final emb = msg[1] as Float32List?;
        _pending.remove(id)?.complete(emb?.toList());
      } else if (msg is String && !ready.isCompleted) {
        ready.completeError(Exception(msg)); // error al cargar el modelo
      }
    });

    _isolate = await Isolate.spawn(_workerMain, [fromWorker.sendPort, modelPath]);
    _worker = await ready.future;
  }

  Future<String> _ensureModel() async {
    final dir = Directory(p.join(
        (await getApplicationSupportDirectory()).path, 'models', 'speaker'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, p.basename(Uri.parse(modelUrl).path)));
    if (await file.exists() && await file.length() > 0) return file.path;

    final tmp = File('${file.path}.part');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(modelUrl));
      final res = await req.close(); // HttpClient sigue redirecciones
      if (res.statusCode != 200) {
        throw HttpException('No se pudo descargar el modelo (${res.statusCode})');
      }
      await res.pipe(tmp.openWrite());
      await tmp.rename(file.path);
    } finally {
      client.close();
    }
    return file.path;
  }

  @override
  Future<List<double>?> embed(Float32List samples) {
    final worker = _worker;
    if (worker == null) return Future.value(null);
    final id = _nextId++;
    final c = Completer<List<double>?>();
    _pending[id] = c;
    worker.send([id, samples]);
    return c.future;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _fromWorker?.close();
    for (final c in _pending.values) {
      c.complete(null);
    }
    _pending.clear();
    _worker = null;
    _isolate = null;
    _preparing = null;
  }
}

/// Isolate de trabajo: carga el modelo una vez y calcula huellas a pedido.
void _workerMain(List<Object> args) {
  final toMain = args[0] as SendPort;
  final modelPath = args[1] as String;

  final sherpa.SpeakerEmbeddingExtractor extractor;
  try {
    sherpa.initBindings(); // hay que llamarlo en cada isolate
    extractor = sherpa.SpeakerEmbeddingExtractor(
      config: sherpa.SpeakerEmbeddingExtractorConfig(
        model: modelPath,
        numThreads: 2,
        debug: false,
      ),
    );
  } catch (e) {
    toMain.send('$e');
    return;
  }

  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);

  inbox.listen((msg) {
    final list = msg as List;
    final id = list[0] as int;
    final samples = list[1] as Float32List;
    Float32List? emb;
    final stream = extractor.createStream();
    try {
      stream
        ..acceptWaveform(samples: samples, sampleRate: 16000)
        ..inputFinished();
      if (extractor.isReady(stream)) {
        final r = extractor.compute(stream);
        emb = r.isEmpty ? null : r;
      }
    } catch (_) {
      emb = null;
    } finally {
      stream.free();
    }
    toMain.send([id, emb]);
  });
}
