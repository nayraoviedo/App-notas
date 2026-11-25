import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      title: 'App Notas',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
    );
  }
}
