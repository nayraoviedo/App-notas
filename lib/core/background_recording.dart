import 'package:flutter/services.dart';

import 'platform_info.dart';

/// Grabar con la pantalla apagada o con Kumo en segundo plano (Android).
///
/// Android le da silencio al micrófono de las apps que no se ven, salvo que
/// tengan un "servicio en primer plano" con un aviso fijo. Ese servicio está
/// en tool/android_widget/kotlin/KumoRecordingService.kt; aquí solo se
/// prende y se apaga. En la compu no hace falta.
class BackgroundRecording {
  BackgroundRecording._();

  static const _channel = MethodChannel('kumo/widget');

  /// Prende el aviso "Kumo está grabando". true si Android lo aceptó.
  static Future<bool> start({String? noteTitle}) async {
    if (!isPhone) return false;
    try {
      return await _channel.invokeMethod<bool>('recordingStart', {
            'title': 'Kumo está grabando 🎙️',
            'text':
                noteTitle == null || noteTitle.isEmpty
                    ? 'Sigue grabando con la pantalla apagada. Toca para volver.'
                    : '$noteTitle · sigue grabando con la pantalla apagada',
          }) ??
          false;
    } catch (_) {
      // Sin el servicio (pruebas, una versión vieja del APK): se graba igual
      // mientras la app esté a la vista.
      return false;
    }
  }

  static Future<void> stop() async {
    if (!isPhone) return;
    try {
      await _channel.invokeMethod<void>('recordingStop');
    } catch (_) {}
  }
}
