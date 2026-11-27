import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Conteos por día guardados en ajustes (pomodoros, repasos…), para el
/// resumen de la semana. Se guardan los últimos 60 días.
class DailyStats {
  static String _key(String name) => 'stats.$name';

  static String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Map<String, int> read(SharedPreferences prefs, String name) {
    try {
      final raw = prefs.getString(_key(name));
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> bump(SharedPreferences prefs, String name, {DateTime? at, int by = 1}) async {
    final m = read(prefs, name);
    final k = day(at ?? DateTime.now());
    m[k] = (m[k] ?? 0) + by;
    final keys = m.keys.toList()..sort();
    while (keys.length > 60) {
      m.remove(keys.removeAt(0));
    }
    await prefs.setString(_key(name), jsonEncode(m));
  }

  /// Suma de [from] (incluido) a [to] (excluido).
  static int sum(SharedPreferences prefs, String name, DateTime from, DateTime to) {
    final a = day(from), b = day(to);
    var n = 0;
    read(prefs, name).forEach((k, v) {
      if (k.compareTo(a) >= 0 && k.compareTo(b) < 0) n += v;
    });
    return n;
  }
}
