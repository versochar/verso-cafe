package com.sosyal.app

import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * Arka plan görevinin kendi FlutterEngine'inde uygulama eklentilerini kaydeder.
 *
 * flutter_foreground_task yalın bir `FlutterEngine(context)` oluşturur ve
 * eklentileri OTOMATİK kaydetmez; bu dinleyici olmadan görev izole edicisinde
 * `flutter_local_notifications` (ve diğer eklentiler) bulunmaz ve
 * "MissingPluginException" verirdi.
 */
object SosyalTaskListener : FlutterForegroundTaskLifecycleListener {
    fun register() {
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(this)
    }

    override fun onEngineCreate(flutterEngine: FlutterEngine?) {
        val engine = flutterEngine ?: return
        GeneratedPluginRegistrant.registerWith(engine)
    }

    override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}
    override fun onTaskRepeatEvent() {}
    override fun onTaskDestroy() {}
    override fun onEngineWillDestroy() {}
}
