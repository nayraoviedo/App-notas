import 'package:flutter/material.dart';

import 'core/widgets/cat_mascot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/fonts.dart';
import 'features/backup/backup_service.dart';
import 'features/settings/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Si se pidió restaurar una copia, se aplica antes de abrir la base.
  try {
    await BackupService.applyPendingRestore();
  } catch (_) {}
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  loadCatPrefs(prefs);
  await loadCustomFonts();
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const AppNotas(),
  ));
}
