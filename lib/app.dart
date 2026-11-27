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
import 'features/notebooks/presentation/pick_notebook_sheet.dart';
import 'features/planner/data/reminder_notifications.dart';
import 'features/planner/domain/planner.dart';
import 'features/recording/application/recording_recovery.dart';
import 'features/planner/presentation/planner_screen.dart';
import 'features/settings/settings.dart';
import 'core/widgets/doodle_icon.dart';

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
    // Las copias de seguridad sacan la base de datos completa y al día.
    BackupService.databaseSnapshot =
        (dest) => ref.read(databaseProvider).customStatement('VACUUM INTO ?', [dest]);
    // En la compu se sube cada 30 min mientras está abierta.
    if (isDesktop) {
      _syncTimer = Timer.periodic(const Duration(minutes: 30), (_) async {
        // Si el otro aparato subió algo, preguntar (si no, esta compu deja de
        // subir sin que se note).
        await _checkNewer();
        await _syncUp();
      });
    }
    _recoverLostPhoto();
    _recoverRecordings();
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
      final weekly = prefs.getBool('week.notify') ?? true;
      await n.scheduleWeeklySummary(on: weekly);
      // El resumen viene prendido: sin permiso (Android 13+) nunca llegaría.
      // Se pide una sola vez, no en cada arranque.
      if (weekly && prefs.getBool('notif.askedOnce') != true) {
        await prefs.setBool('notif.askedOnce', true);
        await n.requestPermission();
      }
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _syncUp();
      // Que el widget quede con lo último que se cambió (horario, pendientes).
      HomeWidget.refresh();
    }
    // Al volver a la app (celular): ¿hay cambios nuevos del otro aparato?
    if (state == AppLifecycleState.resumed && isPhone) _checkNewer();
  }

  DateTime _lastCheck = DateTime(0);
  bool _offering = false;

  /// Si el otro aparato subió cambios más nuevos, ofrecer traerlos. Mientras
  /// eso no se resuelva, este aparato no sube nada a Drive, así que no se
  /// puede quedar callado: se vuelve a preguntar (como mucho cada 2 horas
  /// después de "Ahora no").
  Future<void> _checkNewer() async {
    if (_offering || DateTime.now().difference(_lastCheck) < const Duration(minutes: 10)) return;
    _lastCheck = DateTime.now();
    final prefs = ref.read(sharedPreferencesProvider);
    try {
      if (await BackupService.hasPendingRestore()) return;
      final snooze = prefs.getInt(DriveSync.snoozeKey) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch < snooze) return;
      final newer = await DriveSync.instance.newerFromOtherDevice(prefs);
      if (newer != null) await _offerPull(newer.$1, newer.$2);
    } catch (_) {}
  }

  bool _syncing = false;
  Future<void> _syncUp() async {
    if (_syncing) return;
    _syncing = true;
    try {
      // Después de "Traer cambios" la app se cierra; hasta que se vuelva a
      // abrir, lo de aquí es lo viejo y no se sube.
      if (await BackupService.hasPendingRestore()) return;
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
    try {
      if (await BackupService.hasPendingRestore()) return;
    } catch (_) {}
    // ¿Hay cambios más nuevos desde el otro aparato? Preguntar si traerlos.
    try {
      _lastCheck = DateTime.now();
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
    if (context == null || !context.mounted || _offering) return;
    _offering = true;
    final hm = '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    final String? choice;
    try {
      choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const DoodleText('Hay cambios nuevos ☁️'),
          content: Text('Tu $from guardó cambios en Google Drive (${when.day}/${when.month} $hm).\n\n'
              '• Traer cambios: lo de aquí se reemplaza por esa versión '
              '(antes se guarda una copia de seguridad, por si acaso).\n'
              '• Quedarme con lo de aquí: se sube lo de este aparato y, la próxima vez, '
              'el otro aparato te preguntará si lo trae.\n\n'
              'Mientras no elijas, desde aquí no se sube nada a Drive.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'later'), child: const Text('Ahora no')),
            TextButton(onPressed: () => Navigator.pop(context, 'mine'), child: const Text('Quedarme con lo de aquí')),
            FilledButton(onPressed: () => Navigator.pop(context, 'pull'), child: const Text('Traer cambios')),
          ],
        ),
      );
    } finally {
      _offering = false;
    }
    final prefs = ref.read(sharedPreferencesProvider);
    if (!context.mounted) return;
    final messenger0 = ScaffoldMessenger.maybeOf(context);
    if (choice == 'mine') {
      messenger0?.showSnackBar(const SnackBar(content: Text('Subiendo lo de este aparato…')));
      try {
        await DriveSync.instance.upload(prefs);
        await prefs.remove(DriveSync.snoozeKey);
        messenger0?.hideCurrentSnackBar();
        messenger0?.showSnackBar(const SnackBar(content: Text('Listo: Drive tiene lo de este aparato ✓')));
      } catch (e) {
        messenger0?.hideCurrentSnackBar();
        messenger0?.showSnackBar(SnackBar(content: Text('No se pudo subir: $e')));
      }
      return;
    }
    if (choice != 'pull') {
      // "Ahora no": avisar que la sincronización queda en pausa y volver a
      // preguntar en 2 horas.
      await prefs.setInt(
          DriveSync.snoozeKey, DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch);
      messenger0?.showSnackBar(const SnackBar(
        duration: Duration(seconds: 6),
        content: Text('Sincronización en pausa: lo que hagas aquí no se sube a Drive hasta que elijas. '
            'Te vuelvo a preguntar en 2 horas.'),
      ));
      return;
    }
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
      case 'nota':
        await _noteFromShortcut();
      case 'grabar':
        await _recordFromShortcut();
    }
  }

  /// La clase de ahora (o la que empieza en menos de 15 min), para sugerir
  /// su cuaderno.
  ClassSlot? _classNow(DateTime now) {
    final cls = ref.read(plannerProvider).currentOrNext(now);
    if (cls != null && cls.start - (now.hour * 60 + now.minute) > 15) return null;
    return cls;
  }

  /// Al abrir la app desde el widget, la pantalla tarda un momento en estar.
  Future<BuildContext?> _navContext() async {
    for (var i = 0; i < 40; i++) {
      final nav = appRouter.routerDelegate.navigatorKey.currentContext;
      if (nav != null && nav.mounted) return nav;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  /// "Nota" del widget o del acceso rápido: primero se elige el cuaderno
  /// (sugiriendo el de la clase de ahora) y luego se abre la nota nueva.
  Future<void> _noteFromShortcut() async {
    final now = DateTime.now();
    final cls = _classNow(now);
    String? notebookId = cls?.notebookId;
    final nav = await _navContext();
    if (nav != null && nav.mounted) {
      final choice = await pickNotebookSheet(
        nav,
        ref,
        title: '¿En qué cuaderno va la nota?',
        suggestedId: cls?.notebookId,
        suggestedLabel: cls == null ? null : 'Clase de ahora: ${cls.subject}',
      );
      if (choice == null) return; // se cerró sin elegir: no se crea nada
      notebookId = choice.notebookId;
    }
    final forClass = cls != null && cls.notebookId != null && cls.notebookId == notebookId ? cls : null;
    final id = await ref.read(notesRepositoryProvider).createNote(
          title: forClass != null ? '${forClass.subject} ${now.day}/${now.month}' : 'Nota ${now.day}/${now.month}',
          notebookId: notebookId,
          tags: forClass != null ? [forClass.subject] : const [],
        );
    appRouter.push('/notes/$id');
  }

  /// "Grabar" del widget o del acceso rápido: primero se elige el cuaderno
  /// (sugiriendo el de la clase que hay ahora) y después se empieza a grabar.
  Future<void> _recordFromShortcut() async {
    final now = DateTime.now();
    // Si hay una clase ahora (o empieza pronto), se sugiere su cuaderno.
    final cls = _classNow(now);
    final nav = await _navContext();
    String? notebookId = cls?.notebookId;
    if (nav != null && nav.mounted) {
      final choice = await pickNotebookSheet(
        nav,
        ref,
        title: '¿En qué cuaderno grabo?',
        suggestedId: cls?.notebookId,
        suggestedLabel: cls == null ? null : 'Clase de ahora: ${cls.subject}',
      );
      if (choice == null) return; // se cerró sin elegir: no se graba
      notebookId = choice.notebookId;
    }
    // Si se eligió otro cuaderno que el de la clase, es otra grabación.
    final forClass = cls != null && (cls.notebookId == null || cls.notebookId == notebookId) ? cls : null;
    final id = await ref.read(notesRepositoryProvider).createNote(
          title: forClass != null ? '${forClass.subject} ${now.day}/${now.month}' : 'Grabación ${now.day}/${now.month}',
          notebookId: notebookId,
          tags: forClass != null ? [forClass.subject] : const [],
        );
    appRouter.push('/notes/$id');
    appRouter.push('/notes/$id/record');
  }

  /// Si Android cerró la app mientras la cámara estaba abierta, agrega la
  /// foto a la nota donde se estaba tomando.
  /// Grabaciones que no llegaron a guardarse (Android cerró la app, se
  /// apagó el celular…): se ponen en su nota.
  Future<void> _recoverRecordings() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    try {
      final notes = await recoverInterruptedRecordings(ref.read(notesRepositoryProvider));
      if (notes.isEmpty) return;
      final context = appRouter.routerDelegate.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(notes.length == 1
            ? 'Se recuperó una grabación que no se había terminado de guardar 🎙️'
            : 'Se recuperaron ${notes.length} grabaciones que no se habían terminado de guardar 🎙️'),
        action: SnackBarAction(label: 'Ver', onPressed: () => appRouter.push('/notes/${notes.first}')),
      ));
    } catch (_) {}
  }

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
