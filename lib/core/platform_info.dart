import 'package:flutter/foundation.dart';

/// En el celular (Android/iPhone) hay cosas que en la compu no existen:
/// ML Kit (letra a mano, quitar fondo), la cámara dentro de la app,
/// accesos rápidos, whisper en el teléfono…
///
/// Se usa [defaultTargetPlatform] (y no dart:io) para que las pruebas, que
/// simulan un Android, se comporten como en el celular.
bool get isPhone =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// Windows, Linux o Mac.
bool get isDesktop => !kIsWeb && !isPhone;

/// Mensaje para lo que solo funciona en el celular.
const phoneOnly = 'Esto solo funciona en la app del celular por ahora.';
