import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/planner.dart';

/// Avisos del sistema para exámenes y entregas. Se programan con la hora
/// exacta en UTC, así no depende de la zona horaria del teléfono.
class ReminderNotifications {
  ReminderNotifications._();
  static final instance = ReminderNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Qué hacer al tocar un aviso (lo pone la app: abrir el resumen, etc.).
  void Function(String? payload)? onTap;

  /// Aviso con el que se abrió la app (si fue así).
  String? pendingPayload;

  static const _weeklyId = 0x7FFF0001;

  /// Aviso cada domingo a las 19:00: "tu resumen de la semana".
  Future<void> scheduleWeeklySummary({bool on = true}) async {
    if (!await _init()) return;
    try {
      await _plugin.cancel(id: _weeklyId);
    } catch (_) {}
    if (!on) return;
    final now = DateTime.now();
    var t = DateTime(now.year, now.month, now.day + (7 - now.weekday) % 7, 19);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 7));
    try {
      await _plugin.zonedSchedule(
        id: _weeklyId,
        scheduledDate: tz.TZDateTime.from(t.toUtc(), tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'resumen',
            'Resumen de la semana',
            channelDescription: 'Cada domingo, lo que hiciste y lo que viene',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        title: '🐱 Tu semana en Kumo',
        body: 'Mira lo que hiciste y lo que viene la próxima semana',
        payload: 'week',
      );
    } catch (_) {}
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'pendientes',
      'Exámenes y entregas',
      channelDescription: 'Avisos de tus exámenes, entregas y pendientes',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        pendingPayload = launch?.notificationResponse?.payload;
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Pide permiso de notificaciones (Android 13+). true si se puede avisar.
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final ok = await android?.requestNotificationsPermission();
    return ok ?? true;
  }

  /// Programa (o vuelve a programar) los avisos de un pendiente.
  Future<void> schedule(Reminder r) async {
    await cancel(r);
    if (r.done || !await _init()) return;
    final times = r.alertTimes(DateTime.now());
    for (final (i, t) in times.take(8).indexed) {
      final left = r.due.difference(t);
      final when = left.inMinutes <= 0
          ? 'ahora'
          : left.inHours < 1
              ? 'en ${left.inMinutes} min'
              : left.inHours < 24
                  ? 'en ${left.inHours} h'
                  : 'en ${left.inDays} ${left.inDays == 1 ? 'día' : 'días'}';
      try {
        await _plugin.zonedSchedule(
          id: r.notificationBase + i,
          scheduledDate: tz.TZDateTime.from(t.toUtc(), tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: '${r.kind.emoji} ${r.title}',
          body: '${r.subject.isEmpty ? r.kind.label : r.subject} · $when. ¡Tú puedes! 🐱',
        );
      } catch (_) {
        // Sin permiso o sin servicio de avisos: la lista igual lo muestra.
      }
    }
  }

  Future<void> cancel(Reminder r) async {
    if (!await _init()) return;
    for (var i = 0; i < 8; i++) {
      try {
        await _plugin.cancel(id: r.notificationBase + i);
      } catch (_) {}
    }
  }
}
