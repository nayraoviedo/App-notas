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

/**
 * Servicio "en primer plano" mientras se graba: Android deja usar el
 * micrófono con la pantalla apagada o con otra app encima, y no cierra
 * Kumo a mitad de una clase. Muestra el aviso "Kumo está grabando".
 */
class KumoRecordService : Service() {
    private var wake: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val channelId = "kumo_grabando"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(channelId, "Grabación en curso", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            this, 21,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId) else Notification.Builder(this)
        val notification = builder
            .setContentTitle("Kumo está grabando 🎙️")
            .setContentText("Toca para volver a la grabación")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(4242, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(4242, notification)
            }
        } catch (e: Exception) {
            // Sin permiso o Android no lo deja ahora: se graba igual, como antes.
            stopSelf()
            return START_NOT_STICKY
        }
        if (wake == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "kumo:grabando").apply {
                setReferenceCounted(false)
                acquire(6 * 60 * 60 * 1000L) // como mucho 6 horas
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        try {
            wake?.release()
        } catch (_: Exception) {}
        wake = null
        super.onDestroy()
    }

    companion object {
        fun start(context: Context) {
            val i = Intent(context, KumoRecordService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(i) else context.startService(i)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, KumoRecordService::class.java))
        }
    }
}
