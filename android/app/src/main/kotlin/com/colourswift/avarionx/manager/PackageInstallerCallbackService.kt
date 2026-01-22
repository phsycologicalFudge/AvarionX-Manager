package com.colourswift.avarionx.manager

import android.app.Service
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.IBinder
import io.flutter.plugin.common.EventChannel

class PackageInstallerCallbackService : Service() {

    override fun onStartCommand(intent: Intent, flags: Int, startId: Int): Int {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -999)
        val pkg = intent.getStringExtra("package") ?: ""

        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val confirmation = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            if (confirmation != null) {
                confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(confirmation)
            }
            stopSelf()
            return START_NOT_STICKY
        }

        val ok = status == PackageInstaller.STATUS_SUCCESS
        PackageEventStream.emit(
            mapOf(
                "package" to pkg,
                "action" to (intent.action ?: ""),
                "status" to if (ok) "success" else "failure"
            )
        )

        stopSelf()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent): IBinder? = null
}
