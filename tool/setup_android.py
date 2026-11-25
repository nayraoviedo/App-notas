#!/usr/bin/env python3
"""Ajusta el proyecto Android que genera `flutter create`.

- Agrega los permisos que usa la app (internet, micrófono, cámara).
- Pone el nombre visible "App Notas".
- Sube el minSdk a 24 (lo piden las librerías de voz y transcripción).
- Obliga a todos los plugins a compilar con compileSdk 36: algunos (por
  ejemplo file_picker) traen 34 y la compilación falla con las librerías
  nuevas de AndroidX.

Es seguro correrlo varias veces. Uso (desde la carpeta del proyecto):
    python3 tool/setup_android.py
"""

from pathlib import Path

MANIFEST = Path("android/app/src/main/AndroidManifest.xml")
GRADLE = Path("android/app/build.gradle.kts")
ROOT_GRADLE = Path("android/build.gradle.kts")
FORCE_SDK = Path("android/force_compile_sdk.gradle")
COMPILE_SDK = 36

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

FORCE_SDK.write_text(f"""// Generado por tool/setup_android.py
// Fuerza compileSdk {COMPILE_SDK} en todos los plugins de Flutter.
subprojects {{ p ->
    p.afterEvaluate {{
        if (p.hasProperty('android')) {{
            p.android.compileSdkVersion {COMPILE_SDK}
        }}
    }}
    // El "lint vital" de los plugins no aporta nada a la app y falla con
    // algunas versiones de Java: se desactiva para compilar más rápido.
    p.tasks.matching {{ it.name.startsWith('lintVital') }}.configureEach {{
        it.enabled = false
    }}
}}
""")
root = ROOT_GRADLE.read_text()
line = 'apply(from = "force_compile_sdk.gradle")'
if line not in root:
    ROOT_GRADLE.write_text(line + "\n\n" + root)

print("Android listo: permisos, nombre, minSdk y compileSdk")
