import 'package:app_notas/core/daily_stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('cuenta por día y suma la semana', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await DailyStats.bump(prefs, 'pomodoro', at: DateTime(2026, 11, 23));
    await DailyStats.bump(prefs, 'pomodoro', at: DateTime(2026, 11, 23));
    await DailyStats.bump(prefs, 'pomodoro', at: DateTime(2026, 11, 29));
    await DailyStats.bump(prefs, 'pomodoro', at: DateTime(2026, 11, 30));
    expect(DailyStats.sum(prefs, 'pomodoro', DateTime(2026, 11, 23), DateTime(2026, 11, 30)), 3);
    expect(DailyStats.read(prefs, 'pomodoro')['2026-11-23'], 2);
  });
}
