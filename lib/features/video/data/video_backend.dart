import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../../core/platform_info.dart';
import 'yt_dlp.dart';

/// ¿Es un enlace de YouTube (youtube.com, youtu.be, shorts…)?
bool isYoutubeUrl(String source) => YoutubePlayerController.convertUrlToId(source) != null;

/// ¿Es un enlace web (YouTube o video directo .mp4, .m3u8…)?
bool isWebUrl(String source) =>
    source.startsWith('http://') || source.startsWith('https://');

/// Reproductor de video con lo que necesita la pantalla de notas.
abstract class VideoBackend {
  factory VideoBackend.forSource(String source) =>
      // En la compu no hay WebView: YouTube se abre con el reproductor propio
      // (necesita yt-dlp instalado para enlaces de YouTube).
      isYoutubeUrl(source) && isPhone ? YoutubeBackend(source) : MediaKitBackend(source);

  Widget view();
  Future<void> open({int startMs = 0});
  Future<int> positionMs();
  Future<void> seek(int ms);
  Future<void> play();
  Future<void> pause();

  /// Las capturas solo se pueden en videos propios o enlaces directos.
  /// YouTube no lo permite (ni técnicamente ni por sus condiciones de uso).
  bool get canScreenshot;
  Future<Uint8List?> screenshot();
  Future<void> dispose();
}

/// Videos guardados en el teléfono o enlaces directos (mp4, m3u8…).
class MediaKitBackend implements VideoBackend {
  MediaKitBackend(this.source);
  final String source;
  late final Player _player = Player();
  // En Linux el dibujo del video con la tarjeta gráfica deja la pantalla en
  // negro en varias compus (sobre todo con drivers o procesadores antiguos).
  // Ahí se dibuja con el procesador, que funciona en todas.
  late final VideoController _video = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: !Platform.isLinux,
    ),
  );
  StreamSubscription<String>? _errors;

  /// Para avisar si el reproductor no puede abrir o mostrar el video.
  void Function(String message)? onError;

  @override
  Widget view() => Video(controller: _video);

  /// Para avisar qué está haciendo mientras carga (YouTube en la compu).
  void Function(String status)? onStatus;

  @override
  Future<void> open({int startMs = 0}) async {
    // YouTube en la compu: primero el enlace directo del video.
    // mpv también avisa errores menores: solo se avisa si, un rato después,
    // el video sigue sin imagen.
    _errors ??= _player.stream.error.listen((e) async {
      await Future<void>.delayed(const Duration(seconds: 4));
      if ((_player.state.width ?? 0) == 0) onError?.call(e);
    });
    final Media media;
    String? audioUrl;
    if (isYoutubeUrl(source)) {
      final d = await YtDlp.directUrl(source, onStatus: onStatus);
      media = Media(d.url, httpHeaders: d.headers);
      audioUrl = d.audioUrl;
    } else {
      media = Media(source);
    }
    await _player.open(media, play: false);
    if (audioUrl != null) {
      // YouTube dio el video y el sonido por separado: se suma el sonido.
      await _player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 15), onTimeout: () => Duration.zero);
      final native = _player.platform;
      if (native is NativePlayer) {
        try {
          await native.command(['audio-add', audioUrl, 'select']);
        } catch (_) {}
      }
    }
    if (startMs > 0) {
      // Esperar a que el video sepa su duración antes de saltar.
      await _player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 8), onTimeout: () => Duration.zero);
      await _player.seek(Duration(milliseconds: startMs));
    }
    await _player.play();
  }

  @override
  Future<int> positionMs() async => _player.state.position.inMilliseconds;

  @override
  Future<void> seek(int ms) => _player.seek(Duration(milliseconds: ms));

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  bool get canScreenshot => true;

  @override
  Future<Uint8List?> screenshot() async {
    // Rápido: se piden los píxeles tal cual y se arma el PNG con el motor
    // gráfico (el JPEG de media_kit se codifica en Dart y tarda mucho).
    try {
      final w = _player.state.width, h = _player.state.height;
      final raw = await _player.screenshot(format: null);
      if (raw != null && w != null && h != null && w > 0 && raw.length == w * h * 4) {
        final png = await _rawToPng(raw, w, h);
        if (png != null) return png;
      }
    } catch (_) {}
    return _player.screenshot();
  }

  /// BGRA → PNG, achicado a 1600 px de ancho como máximo (para recortar
  /// rápido y que la foto cargue entera).
  static Future<Uint8List?> _rawToPng(Uint8List raw, int w, int h) async {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(raw, w, h, ui.PixelFormat.bgra8888, done.complete);
    var img = await done.future;
    const maxW = 1600;
    if (w > maxW) {
      final sw = maxW, sh = (h * maxW / w).round();
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImageRect(
        img,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final scaled = await rec.endRecording().toImage(sw, sh);
      img.dispose();
      img = scaled;
    }
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data?.buffer.asUint8List();
  }

  @override
  Future<void> dispose() async {
    await _errors?.cancel();
    await _player.dispose();
  }
}

/// YouTube con su reproductor oficial incrustado.
class YoutubeBackend implements VideoBackend {
  YoutubeBackend(String url)
      : _controller = YoutubePlayerController.fromVideoId(
          videoId: YoutubePlayerController.convertUrlToId(url)!,
          params: const YoutubePlayerParams(
            showFullscreenButton: true,
            strictRelatedVideos: true,
            playsInline: true,
          ),
        );

  final YoutubePlayerController _controller;

  @override
  Widget view() => YoutubePlayer(controller: _controller, aspectRatio: 16 / 9);

  @override
  Future<void> open({int startMs = 0}) async {
    if (startMs > 0) {
      // El reproductor tarda un momento en estar listo.
      await Future<void>.delayed(const Duration(seconds: 2));
      await _controller.seekTo(seconds: startMs / 1000, allowSeekAhead: true);
    }
  }

  @override
  Future<int> positionMs() async => ((await _controller.currentTime) * 1000).round();

  @override
  Future<void> seek(int ms) => _controller.seekTo(seconds: ms / 1000, allowSeekAhead: true);

  @override
  Future<void> play() => _controller.playVideo();

  @override
  Future<void> pause() => _controller.pauseVideo();

  @override
  bool get canScreenshot => false;

  @override
  Future<Uint8List?> screenshot() async => null;

  @override
  Future<void> dispose() => _controller.close();
}
