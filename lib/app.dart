import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/drawing/presentation/painters/stroke_renderer.dart';
import 'features/backup/backup_service.dart';
import 'features/planner/presentation/planner_screen.dart';
import 'features/settings/settings.dart';

class AppNotas extends ConsumerStatefulWidget {
  const AppNotas({super.key});

  @override
  ConsumerState<AppNotas> createState() => _AppNotasState();
}

class _AppNotasState extends ConsumerState<AppNotas> {
  @override
  void initState() {
    super.initState();
    _recoverLostPhoto();
    _setupShortcuts();
    _autoBackup();
  }

  /// Copia de seguridad automática semanal (en segundo plano, al abrir).
  Future<void> _autoBackup() async {
    await Future<void>.delayed(const Duration(seconds: 20)); // que la app abra rápido
    try {
      await BackupService.autoBackupIfDue(ref.read(sharedPreferencesProvider));
    } catch (_) {
      // Sin espacio o sin permiso: se intenta la próxima vez.
    }
  }

  /// Accesos rápidos al mantener presionado el ícono de la app.
  Future<void> _setupShortcuts() async {
    try {
      const actions = QuickActions();
      await actions.initialize(_onShortcut);
      await actions.setShortcutItems(const [
        ShortcutItem(type: 'nota', localizedTitle: 'Nota rápida'),
        ShortcutItem(type: 'grabar', localizedTitle: 'Grabar clase'),
        ShortcutItem(type: 'gasto', localizedTitle: 'Anotar gasto'),
        ShortcutItem(type: 'diario', localizedTitle: 'Mi diario'),
      ]);
    } catch (_) {
      // Sin accesos rápidos (por ejemplo en pruebas): no pasa nada.
    }
  }

  Future<void> _onShortcut(String type) async {
    switch (type) {
      case 'gasto':
        appRouter.push('/expenses');
      case 'diario':
        appRouter.push('/journal');
      case 'nota' || 'grabar':
        final now = DateTime.now();
        // Si hay una clase ahora (o empieza pronto), se graba en su cuaderno.
        final cls = type == 'grabar' ? ref.read(plannerProvider).currentOrNext(now) : null;
        if (cls != null && cls.start - (now.hour * 60 + now.minute) <= 15) {
          final id = await ref.read(notesRepositoryProvider).createNote(
                title: '${cls.subject} ${now.day}/${now.month}',
                notebookId: cls.notebookId,
                tags: [cls.subject],
              );
          appRouter.push('/notes/$id');
          appRouter.push('/notes/$id/record');
          return;
        }
        final id = await ref.read(notesRepositoryProvider).createNote(
              title: type == 'grabar'
                  ? 'Clase ${now.day}/${now.month}'
                  : 'Nota ${now.day}/${now.month}',
            );
        appRouter.push('/notes/$id');
        if (type == 'grabar') appRouter.push('/notes/$id/record');
    }
  }

  /// Si Android cerró la app mientras la cámara estaba abierta, agrega la
  /// foto a la nota donde se estaba tomando.
  Future<void> _recoverLostPhoto() async {
    final lost = await ref.read(cameraServiceProvider).recoverLostPhoto();
    if (lost == null) return;
    final (noteId, path) = lost;
    await ref.read(notesRepositoryProvider).addImageBlock(noteId, path);
    appRouter.push('/notes/$noteId');
  }

  @override
  Widget build(BuildContext context) {
    // Mezcla del resaltador elegida en Ajustes (afecta a todas las hojas).
    StrokeRenderer.highlighterBlend = switch (ref.watch(settingsProvider).highlighterBlend) {
      HighlighterBlend.multiply => BlendMode.multiply,
      HighlighterBlend.darken => BlendMode.darken,
      HighlighterBlend.normal => BlendMode.srcOver,
    };

    return MaterialApp.router(
      title: 'Kumo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(ref.watch(appFontProvider)),
      darkTheme: AppTheme.dark(ref.watch(appFontProvider)),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
    );
  }
}
