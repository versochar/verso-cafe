package com.sosyal.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Arka plan görevinin engine'ine eklentileri kaydetmek için kanca.
        SosyalTaskListener.register()
    }
}
