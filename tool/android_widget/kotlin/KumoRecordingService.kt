package com.appnotas.app_notas

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

// Generado por tool/setup_android.py: mantiene viva la grabación con la
// pantalla apagada o con Kumo en segundo plano. Sin este "servicio en primer
// plano" (con su aviso fijo), Android le da silencio al micrófono de las apps
// que no se ven, y Xiaomi además las cierra.
class KumoRecordingService : Service() {
    companion object {
        private const val CHANNEL = "kumo_grabando"
        private const val NOTIFICATION_ID = 7411
        var running = false
            private set

        fun start(context: Context, title: String, text: String) {
            val i = Intent(context, KumoRecordingService::class.java)
                .putExtra("title", title)
                .putExtra("text", text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, KumoRecordingService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Kumo está grabando"
        val text = intent?.getStringExtra("text") ?: "Toca para volver a la grabación"
        try {
            val n = notification(title, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
        } catch (e: Exception) {
            // Android no dejó (por ejemplo, sin permiso del micrófono): se
            // sigue grabando como antes, solo con la app a la vista.
            stopSelf()
            return START_NOT_STICKY
        }
        running = true
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            // Que el teléfono no se "duerma" del todo con la pantalla apagada.
            // Máximo 6 horas, por si la app se cerrara sin avisar.
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "kumo:grabando").apply {
                setReferenceCounted(false)
                acquire(6 * 60 * 60 * 1000L)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
        }
        wakeLock = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun notification(title: String, text: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(CHANNEL) == null) {
            val ch = NotificationChannel(CHANNEL, "Grabación en curso", NotificationManager.IMPORTANCE_LOW)
            ch.description = "Aviso fijo mientras Kumo graba una clase"
            ch.setSound(null, null)
            manager.createNotificationChannel(ch)
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tap = open?.let {
            PendingIntent.getActivity(this, 21, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        b.setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
        if (tap != null) b.setContentIntent(tap)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return b.build()
    }
}
