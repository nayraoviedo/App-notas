import 'package:flutter/material.dart';

import 'core/widgets/cat_mascot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/fonts.dart';
import 'features/backup/backup_service.dart';
import 'features/settings/settings.dart';
import 'core/files/app_dirs.dart';
import 'core/database/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // En la compu, mudar los datos de versiones viejas (estaban en Documentos).
  await migrateDesktopData();
  // Si se pidió restaurar una copia, se aplica antes de abrir la base.
  try {
    await BackupService.applyPendingRestore();
  } catch (_) {}
  MediaKit.ensureInitialized();
  // En la compu, just_audio suena con el mismo motor que los videos.
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
  final prefs = await SharedPreferences.getInstance();
  loadCatPrefs(prefs);
  // Datos traídos de otro aparato: corregir las rutas de los archivos.
  try {
    if (await needsRebase()) {
      final db = AppDatabase();
      await rebasePaths(db, prefs);
      await db.close();
    }
  } catch (_) {}
  await loadCustomFonts();
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const AppNotas(),
  ));
}
