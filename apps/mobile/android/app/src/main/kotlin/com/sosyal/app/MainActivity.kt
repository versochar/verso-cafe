package com.sosyal.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Arka plan görevinin engine'ine eklentileri kaydetmek için kanca.
        SosyalTaskListener.register()

        // Otomatik güncelleyici kanal: dosya yolu, kurulum izni, kurucu.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "verso/update"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(context.filesDir.absolutePath)

                "canInstall" -> result.success(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        packageManager.canRequestPackageInstalls()
                    else true // 8.0 öncesi kurulum akışı her zaman mümkün
                )

                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    }
                    result.success(null)
                }

                "installApk" -> {
                    val path = call.argument<String>("path")
                    val file = path?.let { File(it) }
                    if (file == null || !file.exists()) {
                        result.error("no_file", "APK bulunamadı: $path", null)
                        return@setMethodCallHandler
                    }
                    val uri = FileProvider.getUriForFile(
                        this, "$packageName.fileprovider", file
                    )
                    startActivity(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_ACTIVITY_NEW_TASK
                            )
                    )
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}
