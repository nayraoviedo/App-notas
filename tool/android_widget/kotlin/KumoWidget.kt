package com.appnotas.app_notas

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Calendar

/**
 * Widget de Kumo en la pantalla de inicio: la clase de ahora (o la que
 * sigue), el próximo pendiente y botones para nota y grabar.
 * Lee el horario que guarda la app ("flutter.planner.data").
 */
class KumoWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) update(context, manager, id)
    }

    companion object {
        const val EXTRA = "kumo_action"

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, KumoWidget::class.java))
            for (id in ids) update(context, manager, id)
        }

        /**
         * Próximo momento en que el widget cambia (empieza o termina una
         * clase, vence un pendiente o cambia el día), para redibujarlo justo
         * ahí y no quedarse mostrando una clase que ya pasó.
         */
        private fun nextChange(context: Context): Long {
            val now = Calendar.getInstance()
            val nowMs = now.timeInMillis
            val midnight = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 5); set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            var best = midnight
            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val raw = prefs.getString("flutter.planner.data", null) ?: return best
                val j = JSONObject(raw)
                val wd = ((now.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
                val dayStart = Calendar.getInstance().apply {
                    set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                }.timeInMillis
                val classes = j.optJSONArray("classes")
                if (classes != null) {
                    for (i in 0 until classes.length()) {
                        val c = classes.getJSONObject(i)
                        if (c.optInt("weekday") != wd) continue
                        for (m in intArrayOf(c.optInt("start"), c.optInt("end"))) {
                            val t = dayStart + m * 60000L + 5000L
                            if (t > nowMs && t < best) best = t
                        }
                    }
                }
                val reminders = j.optJSONArray("reminders")
                if (reminders != null) {
                    for (i in 0 until reminders.length()) {
                        val r = reminders.getJSONObject(i)
                        val t = r.optLong("due") + 5000L
                        if (!r.optBoolean("done") && t > nowMs && t < best) best = t
                    }
                }
            } catch (e: Exception) {}
            return best
        }

        private fun scheduleNext(context: Context) {
            try {
                val ids = AppWidgetManager.getInstance(context)
                    .getAppWidgetIds(ComponentName(context, KumoWidget::class.java))
                val i = Intent(context, KumoWidget::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                val pi = PendingIntent.getBroadcast(context, 21, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                if (ids.isEmpty()) {
                    alarms.cancel(pi)
                    return
                }
                // Sin "exacta": no pide permisos y Android lo agrupa para ahorrar batería
                // (puede llegar unos minutos tarde).
                alarms.set(AlarmManager.RTC, nextChange(context), pi)
            } catch (e: Exception) {}
        }

        private fun hhmm(m: Int) = String.format("%02d:%02d", m / 60, m % 60)

        private fun lines(context: Context): Pair<String, String> {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.planner.data", null) ?: return Pair("Kumo 🐱", "Toca para abrir tus cuadernos")
            return try {
                val j = JSONObject(raw)
                val now = Calendar.getInstance()
                val wd = ((now.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1 // lunes = 1
                val mins = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)

                var title = "Sin más clases hoy 🐱"
                val classes = j.optJSONArray("classes")
                var best: JSONObject? = null
                if (classes != null) {
                    for (i in 0 until classes.length()) {
                        val c = classes.getJSONObject(i)
                        if (c.optInt("weekday") != wd || c.optInt("end") <= mins) continue
                        if (best == null || c.optInt("start") < best.optInt("start")) best = c
                    }
                }
                if (best != null) {
                    val start = best.optInt("start")
                    val room = best.optString("room", "")
                    val whenText = if (start <= mins) "Ahora" else "Hoy ${hhmm(start)}"
                    title = "📚 $whenText · ${best.optString("subject")}" + (if (room.isNotEmpty()) " · $room" else "")
                }

                var body = "Sin pendientes 🎉"
                val reminders = j.optJSONArray("reminders")
                var next: JSONObject? = null
                val nowMs = System.currentTimeMillis()
                if (reminders != null) {
                    for (i in 0 until reminders.length()) {
                        val r = reminders.getJSONObject(i)
                        if (r.optBoolean("done") || r.optLong("due") < nowMs) continue
                        if (next == null || r.optLong("due") < next.optLong("due")) next = r
                    }
                }
                if (next != null) {
                    val due = Calendar.getInstance().apply { timeInMillis = next.optLong("due") }
                    val today = Calendar.getInstance().apply {
                        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                    }
                    val days = ((due.timeInMillis - today.timeInMillis) / 86400000L).toInt()
                    val time = hhmm(due.get(Calendar.HOUR_OF_DAY) * 60 + due.get(Calendar.MINUTE))
                    val whenText = when {
                        days <= 0 -> "hoy $time"
                        days == 1 -> "mañana $time"
                        else -> "en $days días"
                    }
                    val emoji = when (next.optString("kind")) {
                        "exam" -> "📝"
                        "homework" -> "📚"
                        else -> "⏰"
                    }
                    body = "$emoji ${next.optString("title")} · $whenText"
                }
                Pair(title, body)
            } catch (e: Exception) {
                Pair("Kumo 🐱", "Toca para abrir tus cuadernos")
            }
        }

        fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val (title, body) = lines(context)
            val views = RemoteViews(context.packageName, R.layout.kumo_widget)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_body, body)
            views.setOnClickPendingIntent(R.id.widget_root, open(context, "abrir", 11))
            views.setOnClickPendingIntent(R.id.widget_body, open(context, "pendientes", 12))
            views.setOnClickPendingIntent(R.id.widget_note, open(context, "nota", 13))
            views.setOnClickPendingIntent(R.id.widget_record, open(context, "grabar", 14))
            manager.updateAppWidget(id, views)
            scheduleNext(context)
        }

        private fun open(context: Context, action: String, code: Int): PendingIntent {
            val i = Intent(context, MainActivity::class.java).apply {
                this.action = "com.appnotas.KUMO_$action"
                putExtra(EXTRA, action)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(context, code, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}
