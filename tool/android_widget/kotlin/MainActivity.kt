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
        pending = intent?.getStringExtra(KumoWidget.EXTRA)
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
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = intent.getStringExtra(KumoWidget.EXTRA) ?: return
        channel?.invokeMethod("action", action)
    }
}
