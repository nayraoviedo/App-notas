package com.appnotas.app_notas

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Generado por tool/setup_android.py: conecta el widget de inicio con la app.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = takeWidgetAction(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kumo/widget").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        KumoWidget.refreshAll(applicationContext)
                        result.success(null)
                    }
                    "takeAction" -> {
                        result.success(pending)
                        pending = null
                    }
                    // Grabar con la pantalla apagada: aviso fijo "Kumo está grabando".
                    "recordingStart" -> {
                        try {
                            KumoRecordingService.start(
                                applicationContext,
                                call.argument<String>("title") ?: "Kumo está grabando",
                                call.argument<String>("text") ?: "Toca para volver a la grabación",
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "recordingStop" -> {
                        try {
                            KumoRecordingService.stop(applicationContext)
                        } catch (e: Exception) {
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // Mientras se graba, "atrás" en la primera pantalla no cierra Kumo (eso
    // cortaría la grabación): solo lo manda al fondo, como el botón de inicio.
    override fun popSystemNavigator(): Boolean {
        if (KumoRecordingService.running) {
            moveTaskToBack(true)
            return true
        }
        return super.popSystemNavigator()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = takeWidgetAction(intent) ?: return
        channel?.invokeMethod("action", action)
    }

    // Lee el botón del widget una sola vez. Si Android vuelve a abrir la app
    // con el mismo aviso (desde "recientes" o al recrear la pantalla), no se
    // repite: antes eso creaba otra vez la nota que se acababa de borrar.
    private fun takeWidgetAction(intent: Intent?): String? {
        if (intent == null) return null
        val fromHistory = (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        val action = intent.getStringExtra(KumoWidget.EXTRA)
        intent.removeExtra(KumoWidget.EXTRA)
        return if (fromHistory) null else action
    }
}
