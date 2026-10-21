package com.isla0x.haruring

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var native: HaruNative? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "haruring/native")
        val n = HaruNative(this, ch)
        native = n
        ch.setMethodCallHandler { call, result -> n.handle(call, result) }
        n.handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        native?.handleIntent(intent)
    }

    override fun onDestroy() {
        native?.close()
        super.onDestroy()
    }
}
