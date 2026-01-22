package com.colourswift.avarionx.manager

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller

class PackageInstallerReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)

        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val confirmIntent =
                intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)

            confirmIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(confirmIntent)
            return
        }

        val pkg = intent.getStringExtra("package") ?: return
        val ok = status == PackageInstaller.STATUS_SUCCESS

        PackageEventStream.emit(
            mapOf(
                "package" to pkg,
                "action" to "uninstall",
                "status" to if (ok) "success" else "failure"
            )
        )
    }
}
