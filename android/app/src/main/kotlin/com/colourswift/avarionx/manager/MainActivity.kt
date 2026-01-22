package com.colourswift.avarionx.manager

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
import io.flutter.plugin.common.EventChannel

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

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "colourswift_manager/package_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                PackageEventStream.attach(events)
            }

            override fun onCancel(arguments: Any?) {
                PackageEventStream.detach()
            }
        })

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

                "packageInstalledSystem" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    result.success(isInstalledCompat(pkg))
                }

                "getPackageVersionName" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    result.success(versionNameCompat(pkg))
                }

                "packageInstalled" -> {
                    val pkg = call.argument<String>("package") ?: ""
                    result.success(isInstalledCompat(pkg))
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


                "uninstallApk" -> {
                    val pkg = call.argument<String>("package") ?: run {
                        result.error("ARG", "Missing package", null)
                        return@setMethodCallHandler
                    }

                    uninstallPackage(pkg)
                    result.success(null)
                }

                "injectCert" -> {
                    val packageName = call.argument<String>("package")!!
                    val content = call.argument<String>("content") ?: "shizuku=enabled"

                    if (!Shizuku.pingBinder()) {
                        result.error("SHIZUKU", "Shizuku not running", null)
                        return@setMethodCallHandler
                    }

                    if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                        result.error("SHIZUKU", "Permission not granted", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val cmd = arrayOf(
                            "sh", "-c",
                            """
mkdir -p /storage/emulated/0/Android/data/$packageName/files &&
printf "%s" "$content" > /storage/emulated/0/Android/data/$packageName/files/cs_shizuku.cert
                    """.trimIndent()
                        )

                        val process = Shizuku::class.java
                            .getDeclaredMethod(
                                "newProcess",
                                Array<String>::class.java,
                                Array<String>::class.java,
                                String::class.java
                            )
                            .apply { isAccessible = true }
                            .invoke(null, cmd, null, null) as Process

                        val exit = process.waitFor()
                        if (exit != 0) {
                            throw RuntimeException("Shell write failed ($exit)")
                        }

                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("INJECT", t.message, null)
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isInstalledCompat(pkg: String): Boolean {
        return try {
            if (android.os.Build.VERSION.SDK_INT >= 33) {
                packageManager.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(pkg, 0)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun versionNameCompat(pkg: String): String {
        return try {
            val info = if (android.os.Build.VERSION.SDK_INT >= 33) {
                packageManager.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(pkg, 0)
            }
            info.versionName ?: ""
        } catch (e: Exception) {
            ""
        }
    }

    private fun uninstallPackage(packageName: String) {

        val intent = Intent(this, UninstallReceiver::class.java).apply {
            action = "colourswift.ACTION_UNINSTALL"
            putExtra("package", packageName)
        }

        val pending = PendingIntent.getBroadcast(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        packageManager.packageInstaller.uninstall(
            packageName,
            pending.intentSender
        )
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