import 'package:flutter/services.dart';

/// Puente con el widget de la pantalla de inicio (código en
/// tool/android_widget). El widget lee el horario guardado por la app; aquí
/// solo se le pide que se redibuje y se reciben sus botones.
class HomeWidget {
  HomeWidget._();

  static const _channel = MethodChannel('kumo/widget');

  /// Vuelve a dibujar el widget (después de cambiar el horario o pendientes).
  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod<void>('update');
    } catch (_) {
      // Sin widget (pruebas, iPhone…): no pasa nada.
    }
  }

  /// [onAction] recibe "nota", "grabar", "pendientes" o "abrir" cuando se
  /// toca un botón del widget (al abrir la app o con la app ya abierta).
  static Future<void> listen(void Function(String action) onAction) async {
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'action' && call.arguments is String) onAction(call.arguments as String);
      });
      final first = await _channel.invokeMethod<String>('takeAction');
      if (first != null) onAction(first);
    } catch (_) {}
  }
}
