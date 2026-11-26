import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import 'core/home_widget.dart';
import 'core/platform_info.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/drawing/presentation/painters/stroke_renderer.dart';
import 'features/backup/backup_service.dart';
import 'features/backup/drive_sync.dart';
import 'features/planner/data/reminder_notifications.dart';
import 'features/planner/presentation/planner_screen.dart';
import 'features/settings/settings.dart';

class AppNotas extends ConsumerStatefulWidget {
  const AppNotas({super.key});

  @override
  ConsumerState<AppNotas> createState() => _AppNotasState();
}

class _AppNotasState extends ConsumerState<AppNotas> with WidgetsBindingObserver {
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // En la compu se sube cada 30 min mientras está abierta.
    if (isDesktop) {
      _syncTimer = Timer.periodic(const Duration(minutes: 30), (_) => _syncUp());
    }
    _recoverLostPhoto();
    _setupShortcuts();
    _autoBackup();
    _setupWidgetAndWeekly();
  }

  /// Widget de inicio y aviso del resumen de los domingos.
  Future<void> _setupWidgetAndWeekly() async {
    HomeWidget.refresh();
    HomeWidget.listen((a) => switch (a) {
          'nota' || 'grabar' => _onShortcut(a),
          'pendientes' => appRouter.push('/planner?tab=pendientes'),
          _ => null,
        });
    final n = ReminderNotifications.instance;
    n.onTap = (payload) {
      if (payload == 'week') appRouter.push('/week');
    };
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await n.scheduleWeeklySummary(on: prefs.getBool('week.notify') ?? true);
      if (n.pendingPayload == 'week') {
        n.pendingPayload = null;
        appRouter.push('/week');
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  /// Al salir de la app (celular), subir los cambios a Drive.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _syncUp();
  }

  bool _syncing = false;
  Future<void> _syncUp() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await DriveSync.instance.syncUpIfDue(ref.read(sharedPreferencesProvider));
    } catch (_) {
      // Sin internet, sin espacio o sin permiso: se intenta la próxima vez.
    } finally {
      _syncing = false;
    }
  }

  /// Copia de seguridad automática semanal y sincronización (al abrir).
  Future<void> _autoBackup() async {
    await Future<void>.delayed(const Duration(seconds: 6)); // que la app abra rápido
    final prefs = ref.read(sharedPreferencesProvider);
    // ¿Hay cambios más nuevos desde el otro aparato? Preguntar si traerlos.
    try {
      final newer = await DriveSync.instance.newerFromOtherDevice(prefs);
      if (newer != null) {
        await _offerPull(newer.$1, newer.$2);
        return;
      }
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 14));
    try {
      await BackupService.autoBackupIfDue(prefs);
    } catch (_) {}
    await _syncUp();
  }

  Future<void> _offerPull(DateTime when, String from) async {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final hm = '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hay cambios nuevos ☁️'),
        content: Text('Tu $from guardó cambios en Google Drive (${when.day}/${when.month} $hm).\n\n'
            '¿Traerlos a este aparato? Lo que hay aquí se reemplaza por esa versión '
            '(antes se guarda una copia de seguridad, por si acaso).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Traer cambios')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(const SnackBar(content: Text('Trayendo los cambios…'), duration: Duration(minutes: 5)));
    try {
      await DriveSync.instance.restoreLatest(ref.read(sharedPreferencesProvider));
      messenger?.hideCurrentSnackBar();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Cambios listos ✓'),
          content: const Text('Kumo se tiene que cerrar para terminar. Vuelve a abrirlo y verás todo al día.'),
          actions: [
            FilledButton(
              onPressed: () => isDesktop ? exit(0) : SystemNavigator.pop(),
              child: const Text('Cerrar Kumo'),
            ),
          ],
        ),
      );
    } catch (e) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text('No se pudieron traer los cambios: $e')));
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
