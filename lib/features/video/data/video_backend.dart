import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// ¿Es un enlace de YouTube (youtube.com, youtu.be, shorts…)?
bool isYoutubeUrl(String source) => YoutubePlayerController.convertUrlToId(source) != null;

/// ¿Es un enlace web (YouTube o video directo .mp4, .m3u8…)?
bool isWebUrl(String source) =>
    source.startsWith('http://') || source.startsWith('https://');

/// Reproductor de video con lo que necesita la pantalla de notas.
abstract class VideoBackend {
  factory VideoBackend.forSource(String source) =>
      isYoutubeUrl(source) ? YoutubeBackend(source) : MediaKitBackend(source);

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
  late final VideoController _video = VideoController(_player);

  @override
  Widget view() => Video(controller: _video);

  @override
  Future<void> open({int startMs = 0}) async {
    await _player.open(Media(source), play: false);
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
  Future<Uint8List?> screenshot() => _player.screenshot();

  @override
  Future<void> dispose() => _player.dispose();
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
