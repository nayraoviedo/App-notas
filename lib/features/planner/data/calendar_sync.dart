import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/google_auth.dart';
import '../domain/planner.dart';

/// Pasa los exámenes y entregas a tu Google Calendar (calendario principal).
/// Cada pendiente se vuelve un evento; si lo cambias o lo borras en Kumo,
/// también cambia allá. Se usa la misma cuenta de Google que para Drive.
class CalendarSync {
  CalendarSync._();
  static final instance = CalendarSync._();

  static const scopes = ['https://www.googleapis.com/auth/calendar.events'];
  static const onKey = 'google.calendar.on';
  static const _mapKey = 'google.calendar.events'; // id del pendiente → id del evento
  static const _sigKey = 'google.calendar.sigs'; // id del pendiente → huella

  bool isOn(SharedPreferences prefs) => prefs.getBool(onKey) ?? false;

  Map<String, String> _read(SharedPreferences prefs, String key) {
    try {
      return (jsonDecode(prefs.getString(key) ?? '{}') as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  /// Activa (pide permiso de Calendar) y sincroniza todo.
  Future<int> enable(SharedPreferences prefs, List<Reminder> reminders) async {
    await GoogleAuth.instance.token(prefs, scopes, interactive: true);
    await prefs.setBool(onKey, true);
    return sync(prefs, reminders);
  }

  Future<void> disable(SharedPreferences prefs) => prefs.setBool(onKey, false);

  static String _sig(Reminder r) =>
      '${r.title}|${r.due.toIso8601String()}|${r.kind.name}|${r.subject}|${r.done}';

  /// Crea, actualiza o borra eventos para que coincidan con [reminders].
  /// Devuelve cuántos eventos cambió.
  ///
  /// Si ya hay una sincronización en curso, no se lanza otra a la vez (dos a
  /// la vez crean el mismo evento dos veces): se espera y luego se corre una
  /// sola vez más con la lista más nueva.
  Future<int> sync(SharedPreferences prefs, List<Reminder> reminders) {
    _latest = reminders;
    final running = _running;
    if (running != null) {
      return _again ??= running.then((_) {
        _again = null;
        return _start(prefs);
      }, onError: (_) {
        _again = null;
        return _start(prefs);
      });
    }
    return _start(prefs);
  }

  Future<int>? _running;
  Future<int>? _again;
  List<Reminder> _latest = const [];

  Future<int> _start(SharedPreferences prefs) {
    final f = _syncNow(prefs, _latest);
    _running = f;
    f.whenComplete(() {
      if (identical(_running, f)) _running = null;
    }).ignore();
    return f;
  }

  Future<int> _syncNow(SharedPreferences prefs, List<Reminder> reminders) async {
    if (!isOn(prefs)) return 0;
    final token = await GoogleAuth.instance.token(prefs, scopes);
    final h = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final events = _read(prefs, _mapKey);
    final sigs = _read(prefs, _sigKey);
    var changed = 0;
    const base = 'https://www.googleapis.com/calendar/v3/calendars/primary/events';

    final ids = {for (final r in reminders) r.id};
    // Borrados en Kumo → borrar el evento.
    for (final id in events.keys.where((k) => !ids.contains(k)).toList()) {
      await http.delete(Uri.parse('$base/${events[id]}'), headers: h);
      events.remove(id);
      sigs.remove(id);
      changed++;
    }

    for (final r in reminders) {
      final sig = _sig(r);
      if (sigs[r.id] == sig && events.containsKey(r.id)) continue;
      // Pendientes ya pasados que nunca se subieron: no hace falta.
      if (!events.containsKey(r.id) && r.due.isBefore(DateTime.now().subtract(const Duration(days: 1)))) continue;
      final start = r.due;
      final body = jsonEncode({
        'summary': '${r.kind.emoji} ${r.done ? '✓ ' : ''}${r.title}',
        'description': [
          if (r.subject.isNotEmpty) 'Materia: ${r.subject}',
          '${r.kind.label} anotado en Kumo',
        ].join('\n'),
        'start': {'dateTime': start.toUtc().toIso8601String()},
        'end': {'dateTime': start.add(const Duration(hours: 1)).toUtc().toIso8601String()},
        'reminders': {
          'useDefault': false,
          'overrides': [
            for (final b in r.notifyBefore.take(5)) {'method': 'popup', 'minutes': b.inMinutes.clamp(0, 40320)},
          ],
        },
        'extendedProperties': {
          'private': {'kumoId': r.id},
        },
        'colorId': switch (r.kind) {
          ReminderKind.exam => '11',
          ReminderKind.homework => '5',
          ReminderKind.other => '2',
        },
      });
      // ¿Ya lo creó el otro aparato? (se busca por el id de Kumo)
      var existing = events[r.id];
      if (existing == null) {
        final found = await http.get(
          Uri.parse(base).replace(queryParameters: {'privateExtendedProperty': 'kumoId=${r.id}', 'maxResults': '1'}),
          headers: h,
        );
        if (found.statusCode == 200) {
          final items = (jsonDecode(found.body) as Map)['items'] as List? ?? const [];
          if (items.isNotEmpty) existing = (items.first as Map)['id'] as String?;
        }
      }
      http.Response res;
      if (existing != null) {
        res = await http.put(Uri.parse('$base/$existing'), headers: h, body: body);
        if (res.statusCode == 404 || res.statusCode == 410) {
          // Lo borraron en Calendar: crearlo de nuevo.
          res = await http.post(Uri.parse(base), headers: h, body: body);
        }
      } else {
        res = await http.post(Uri.parse(base), headers: h, body: body);
      }
      if (res.statusCode == 403 && res.body.contains('accessNotConfigured')) {
        throw const GoogleAuthException('Falta activar "Google Calendar API" en tu proyecto de Google Cloud.');
      }
      if (res.statusCode >= 300) throw GoogleAuthException('Google Calendar respondió ${res.statusCode}.');
      events[r.id] = (jsonDecode(res.body) as Map)['id'] as String;
      sigs[r.id] = sig;
      changed++;
    }
    await prefs.setString(_mapKey, jsonEncode(events));
    await prefs.setString(_sigKey, jsonEncode(sigs));
    return changed;
  }
}
