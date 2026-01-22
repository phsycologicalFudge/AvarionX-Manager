package com.colourswift.avarionx.manager

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller

class UninstallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE
        )

        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirmation = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            if (confirmation != null) {
                confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(confirmation)
            }
            return
        }

        val packageName = intent.getStringExtra("package") ?: return

        PackageEventStream.emit(
            mapOf(
                "package" to packageName,
                "action" to "uninstall",
                "status" to status,
                "success" to (status == PackageInstaller.STATUS_SUCCESS)
            )
        )
    }
}
