package com.example.colourswift_manager

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {

    private val channel = "colourswift_manager/shizuku"
    private val requestCode = 0xCA07A

    private var lastPermissionResult: Int? = null

    private val permissionListener =
        Shizuku.OnRequestPermissionResultListener { code, result ->
            if (code == requestCode) {
                lastPermissionResult = result
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Shizuku.addRequestPermissionResultListener(permissionListener)
    }

    override fun onDestroy() {
        Shizuku.removeRequestPermissionResultListener(permissionListener)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channel
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "ping" -> {
                    result.success(Shizuku.pingBinder())
                }

                "hasPermission" -> {
                    result.success(
                        Shizuku.checkSelfPermission() ==
                                PackageManager.PERMISSION_GRANTED
                    )
                }

                "requestPermission" -> {
                    if (!Shizuku.isPreV11()) {
                        Shizuku.requestPermission(requestCode)
                    }
                    result.success(null)
                }

                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("ARG", "Missing path", null)
                        return@setMethodCallHandler
                    }

                    try {
                        installApkWithShizuku(path)
                        result.success(true)
                    } catch (e: Throwable) {
                        result.error("INSTALL", e.message, null)
                    }
                }

                "injectCert" -> {
                    val packageName = call.argument<String>("package")!!
                    val content = call.argument<String>("content") ?: "shizuku=enabled"

                    val path = "/storage/emulated/0/Android/data/$packageName/files"
                    val file = File(path, "cs_shizuku.cert")

                    file.parentFile?.mkdirs()
                    file.writeText(content)

                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun installApkWithShizuku(path: String) {

        if (!Shizuku.pingBinder()) {
            throw IllegalStateException("Shizuku not running")
        }

        if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("Shizuku permission not granted")
        }

        val clazz = Shizuku::class.java
        val method = clazz.getDeclaredMethod(
            "newProcess",
            Array<String>::class.java,
            Array<String>::class.java,
            String::class.java
        )

        method.isAccessible = true

        val process = method.invoke(
            null,
            arrayOf("pm", "install", "-r", path),
            null,
            null
        ) as Process

        val exitCode = process.waitFor()
        if (exitCode != 0) {
            throw RuntimeException("pm install failed with exit code $exitCode")
        }
    }
}