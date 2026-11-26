#!/usr/bin/env python3
"""Ajusta el proyecto Android que genera `flutter create`.

- Agrega los permisos que usa la app (internet y micrófono). La cámara se
  usa a través de la app de cámara del sistema y no necesita permiso.
- Pone el nombre visible "Kumo".
- Sube el minSdk a 24 (lo piden las librerías de voz y transcripción).
- Obliga a todos los plugins a compilar con compileSdk 36: algunos (por
  ejemplo file_picker) traen 34 y la compilación falla con las librerías
  nuevas de AndroidX.

Es seguro correrlo varias veces. Uso (desde la carpeta del proyecto):
    python3 tool/setup_android.py
"""

import shutil
from pathlib import Path

MANIFEST = Path("android/app/src/main/AndroidManifest.xml")
GRADLE = Path("android/app/build.gradle.kts")
ROOT_GRADLE = Path("android/build.gradle.kts")
FORCE_SDK = Path("android/force_compile_sdk.gradle")
COMPILE_SDK = 36

PERMISSIONS = """
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
"""

# Dentro de <application>: avisos programados (también después de reiniciar)
# y la descarga automática del modelo para quitar fondos.
APP_EXTRAS = """
        <meta-data android:name="com.google.mlkit.vision.DEPENDENCIES" android:value="subject_segment" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""

s = MANIFEST.read_text()
# La app usa su propia cámara (paquete camera), así que declara CAMERA y lo
# pide al abrirla. Ya no abre la cámara del sistema: eso hacía que Android
# cerrara la app mientras tanto.
if "RECORD_AUDIO" not in s:
    i = s.index(">", s.index("<manifest")) + 1
    s = s[:i] + PERMISSIONS + s[i:]
s = s.replace('android:label="app_notas"', 'android:label="Kumo"')
# Copia automática en la cuenta de Google (reglas en res/xml/).
if "fullBackupContent" not in s:
    s = s.replace("<application", '<application android:allowBackup="true" '
                  'android:fullBackupContent="@xml/backup_rules" '
                  'android:dataExtractionRules="@xml/data_extraction_rules"', 1)
if "ScheduledNotificationReceiver" not in s:
    i = s.index(">", s.index("<application")) + 1
    s = s[:i] + APP_EXTRAS + s[i:]
if "POST_NOTIFICATIONS" not in s:
    i = s.index(">", s.index("<manifest")) + 1
    s = s[:i] + """
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
""" + s[i:]
MANIFEST.write_text(s)

g = GRADLE.read_text()
g = g.replace("minSdk = flutter.minSdkVersion", "minSdk = maxOf(24, flutter.minSdkVersion)")
# flutter_local_notifications necesita "desugaring" de Java.
if "isCoreLibraryDesugaringEnabled" not in g:
    g = g.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    g += """
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
"""
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

# Ícono de la app: el gatito leyendo (tool/android_icon/res), también como
# ícono adaptable para Android 8+ (fondo crema + gatito al centro).
ICON_RES = Path(__file__).parent / "android_icon" / "res"
if ICON_RES.exists():
    shutil.copytree(ICON_RES, Path("android/app/src/main/res"), dirs_exist_ok=True)

# Menos memoria para Gradle: con todas las librerías nativas el servidor de
# GitHub se quedaba sin memoria y cortaba la compilación.
PROPS = Path("android/gradle.properties")
props = PROPS.read_text() if PROPS.exists() else ""
lines = [l for l in props.splitlines() if not l.startswith(("org.gradle.jvmargs", "org.gradle.workers.max", "kotlin.daemon.jvmargs"))]
lines += [
    "org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g -XX:+HeapDumpOnOutOfMemoryError",
    "kotlin.daemon.jvmargs=-Xmx2g",
    "org.gradle.workers.max=3",
]
PROPS.write_text("\n".join(lines) + "\n")

# Firma fija del APK (tool/firma): así las actualizaciones se instalan
# encima sin perder datos, y el inicio de sesión con Google reconoce la app
# (Google Cloud registra la huella SHA-1 de esta firma).
FIRMA = Path(__file__).parent / "firma"
if (FIRMA / "kumo.jks").exists():
    shutil.copy(FIRMA / "kumo.jks", Path("android/app/kumo.jks"))
    shutil.copy(FIRMA / "key.properties", Path("android/key.properties"))
    g = GRADLE.read_text()
    if "signingConfigs.getByName(\"kumo\")" not in g:
        if not g.startswith("import java.util.Properties"):
            g = "import java.util.Properties\n" + g
        props = (
            '\nval kumoKeys = Properties().apply {\n'
            '    val f = rootProject.file("key.properties")\n'
            '    if (f.exists()) f.inputStream().use { load(it) }\n'
            '}\n'
        )
        i = g.index("android {")
        g = g[:i] + props + "\n" + g[i:]
        signing = (
            '    signingConfigs {\n'
            '        create("kumo") {\n'
            '            keyAlias = kumoKeys["keyAlias"] as String\n'
            '            keyPassword = kumoKeys["keyPassword"] as String\n'
            '            storeFile = file(kumoKeys["storeFile"] as String)\n'
            '            storePassword = kumoKeys["storePassword"] as String\n'
            '        }\n'
            '    }\n\n'
        )
        j = g.index("    buildTypes {")
        g = g[:j] + signing + g[j:]
        g = g.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("kumo")')
        GRADLE.write_text(g)

# Widget de inicio (próxima clase, pendiente y botones). Va sin plugin: el
# código Kotlin está en tool/android_widget y reemplaza el MainActivity
# que genera `flutter create`.
WIDGET = Path(__file__).parent / "android_widget"
if WIDGET.exists():
    shutil.copytree(WIDGET / "res", Path("android/app/src/main/res"), dirs_exist_ok=True)
    mains = list(Path("android/app/src/main").rglob("MainActivity.kt"))
    kdir = mains[0].parent if mains else Path("android/app/src/main/kotlin/com/appnotas/app_notas")
    pkg = "com.appnotas.app_notas"
    for m in mains:
        for line in m.read_text().splitlines():
            if line.startswith("package "):
                pkg = line.split()[1].strip()
    for m in mains:
        m.unlink()
    for java in Path("android/app/src/main").rglob("MainActivity.java"):
        java.unlink()
    kdir.mkdir(parents=True, exist_ok=True)
    for name in ("MainActivity.kt", "KumoWidget.kt"):
        code = (WIDGET / "kotlin" / name).read_text().replace("package com.appnotas.app_notas", f"package {pkg}", 1)
        (kdir / name).write_text(code)
    s = MANIFEST.read_text()
    if "KumoWidget" not in s:
        receiver = """
        <receiver android:name=".KumoWidget" android:exported="false" android:label="Kumo">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/kumo_widget_info" />
        </receiver>
"""
        i = s.index(">", s.index("<application")) + 1
        s = s[:i] + receiver + s[i:]
        MANIFEST.write_text(s)
    print("Widget de inicio listo")

# Reglas para R8: el lector de letra trae WorkManager, que crea su base de
# datos (Room) por reflexión. Sin esto, la app se cierra al abrir con
# "Failed to create an instance of androidx.work.impl.WorkDatabase".
PROGUARD = Path("android/app/proguard-rules.pro")
rules = """
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(...); }
-keep class **_Impl { <init>(...); }
-dontwarn androidx.work.**
"""
old = PROGUARD.read_text() if PROGUARD.exists() else ""
if "androidx.work" not in old:
    PROGUARD.write_text(old + rules)
g = GRADLE.read_text()
if "proguard-rules.pro" not in g:
    import re
    g = re.sub(
        r'(signingConfig = signingConfigs\.getByName\("(?:kumo|debug)"\))',
        r'\1\n            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")',
        g,
        count=1,
    )
    GRADLE.write_text(g)
print("Reglas de R8 listas")
