#!/usr/bin/env python3
"""Ajusta el proyecto Android que genera `flutter create`.

- Agrega los permisos que usa la app (internet, micrófono, cámara).
- Pone el nombre visible "App Notas".
- Sube el minSdk a 24 (lo piden las librerías de voz y transcripción).

Es seguro correrlo varias veces. Uso (desde la carpeta del proyecto):
    python3 tool/setup_android.py
"""

from pathlib import Path

MANIFEST = Path("android/app/src/main/AndroidManifest.xml")
GRADLE = Path("android/app/build.gradle.kts")

PERMISSIONS = """
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
"""

s = MANIFEST.read_text()
if "RECORD_AUDIO" not in s:
    i = s.index(">", s.index("<manifest")) + 1
    s = s[:i] + PERMISSIONS + s[i:]
s = s.replace('android:label="app_notas"', 'android:label="App Notas"')
MANIFEST.write_text(s)

g = GRADLE.read_text()
g = g.replace("minSdk = flutter.minSdkVersion", "minSdk = maxOf(24, flutter.minSdkVersion)")
GRADLE.write_text(g)

print("Android listo: permisos, nombre y minSdk")
