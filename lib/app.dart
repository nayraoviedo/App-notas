import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/drawing/presentation/painters/stroke_renderer.dart';
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
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
    );
  }
}
