# App-notas

App de notas en Flutter: cuadernos con portada, escribir con distintas fuentes,
escribir a mano y dibujar con pinceles, lápices y capas, grabar audio con
transcripción, tomar fotos, importar PDFs para escribir encima y ver videos
tomando notas. Funciona sin internet.

## Puesta en marcha

```bash
# 1. Generar las carpetas android/ e ios/ (no están en el repo todavía)
flutter create . --org com.appnotas --project-name app_notas --platforms android,ios

# 2. Dependencias
flutter pub get

# 3. Generar el código de la base de datos (drift)
dart run build_runner build --delete-conflicting-outputs

# 4. Correr
flutter run
```

> Si `flutter pub get` da conflictos de versiones, prueba
> `flutter pub upgrade --major-versions`.

### Permisos

**Android** – en `android/app/src/main/AndroidManifest.xml`, dentro de `<manifest>`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
```

`minSdkVersion` 24 o más en `android/app/build.gradle`.

**iOS** – en `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Para grabar y transcribir tus notas de voz.</string>
<key>NSCameraUsageDescription</key>
<string>Para agregar fotos a tus notas.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Para agregar fotos y videos de tu galería.</string>
```

Y la versión mínima de iOS en 15.6 (`ios/Podfile` → `platform :ios, '15.6'`),
que la pide `whisper_ggml`.

### Notas sobre dependencias

- **Base de datos:** el esquema va en la versión 2 (cuadernos y fuentes). La
  migración desde la 1 ya está escrita en `app_database.dart`.
- **Fuentes sin internet:** Google Fonts las descarga la primera vez. Para
  incluirlas en la app, baja los `.ttf` a `assets/google_fonts/`, decláralos
  en `pubspec.yaml` y llama a `GoogleFonts.config.allowRuntimeFetching = false`.
- **Modelo de voz:** se descarga a la carpeta de soporte de la app. Para otro
  idioma o tamaño, cambia `SherpaVoiceEmbedder.defaultModelUrl` por otro modelo
  de https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models
- **iOS y `file_picker`/`pdfx`:** revisa sus README por si piden ajustes en
  `Info.plist` o `Podfile`.

## Arquitectura

Organizada por funcionalidades (feature-first), cada una con sus capas:

```
lib/
  core/                 base de datos (drift), archivos, rutas, tema, fuentes, providers
  features/
    notebooks/          cuadernos con portada (pantalla principal)
    notes/              notas hechas de bloques (texto, audio, imagen, hoja, video)
    drawing/            hojas a mano: plantillas, herramientas, capas, deshacer
    importing/          PDF y fotos → hojas para escribir encima
    recording/          grabación: micrófono → WAV + transcripción en vivo
    transcription/      Whisper en el teléfono + unión en párrafos
    speakers/           detección de cambio de voz y confirmación
    camera/             fotos y selección de videos
    video/              ver video + notas con minuto + capturas
```

- **Estado:** Riverpod. **Navegación:** go_router. **Datos:** drift (SQLite).
  Los archivos van a disco y la base de datos guarda solo las rutas.
- **Una nota = lista de bloques.** Así una nota mezcla texto, grabaciones,
  fotos y referencias a videos.
- **Anclas de tiempo:** fotos tomadas durante una grabación y capturas de
  video guardan el minuto exacto, y al tocarlas el audio o video salta ahí.

### Cómo funciona una grabación

1. `record` entrega audio PCM 16 kHz en vivo.
2. Ese audio va a tres lugares a la vez:
   - un archivo WAV (con cabecera actualizada cada 10 s, para no perder el
     audio si la app se cierra),
   - Whisper en vivo (texto aproximado en pantalla),
   - el detector de cambio de voz.
3. Si la voz cambia, aparece *"¿Habla otra persona?"* con opciones. También se
   puede tocar "¿Quién habla?" arriba para indicarlo a mano.
4. Al terminar, Whisper transcribe el archivo completo con un modelo mejor y
   `SegmentMerger` une los fragmentos cortos en párrafos por persona.
5. Se guardan el audio, los párrafos, las marcas ⭐ y las fotos con su minuto.

## Estado actual y próximos pasos

- [x] Notas por bloques, editar texto, borrar, renombrar
- [x] Grabación con transcripción en vivo y final, en párrafos
- [x] ⭐ Marcar momentos importantes y filtrar por ellos
- [x] Fotos sincronizadas con el minuto de la grabación
- [x] Búsqueda en títulos, texto y en lo que se dijo en los audios
- [x] Video + notas con minuto + capturas del video
- [x] Marcar a mano quién habla
- [x] Detección automática de cambio de voz con `sherpa_onnx` (en un isolate;
      el modelo se descarga la primera vez, ~40 MB)
- [x] Cuadernos con color o imagen de portada; mover notas entre cuadernos
- [x] Hojas a mano: 7 plantillas (blanca, rayada, cuadros, puntos, Cornell,
      tareas, pentagrama), 5 colores de hoja, separación, vertical/horizontal
      y **hoja personalizada** desde una imagen
- [x] Herramientas: bolígrafo, lápiz, pincel, marcador, resaltador, borrador
      y "borrar trazos completos", con color y grosor por herramienta y
      presión del lápiz óptico; modo "solo lápiz óptico"
- [x] Capas: crear, duplicar, ocultar, bloquear, opacidad, renombrar,
      reordenar, vaciar y eliminar; deshacer/rehacer
- [x] Importar PDF (nota nueva o dentro de una nota) y fotos como hojas
- [x] Fuentes y tamaños por bloque de texto (Google Fonts)
- [ ] Servicio en primer plano en Android para grabar con la pantalla apagada
- [ ] Editor enriquecido (`flutter_quill`): negritas, listas, checklists
- [ ] Vocabulario por materia/proyecto (`RecordingController.vocabulary`)
- [ ] Resumen, tareas y preguntas abiertas al terminar una grabación
- [ ] Texto escrito con teclado dentro de las hojas (cuadros de texto) y
      herramienta lazo para mover trazos
- [ ] Reconocer escritura a mano para que también se pueda buscar
- [ ] Búsqueda con FTS5, exportar a PDF/Markdown, sincronización en la nube
