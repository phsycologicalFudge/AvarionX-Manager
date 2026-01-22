package com.colourswift.avarionx.manager

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller

class PackageEventReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {

        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE
        )

        val pkg = intent.getStringExtra("package") ?: return

        if (status == PackageInstaller.STATUS_SUCCESS) {
            PackageEventStream.emit(
                mapOf(
                    "package" to pkg,
                    "action" to "uninstall",
                    "status" to "success"
                )
            )
        } else {
            val msg = intent.getStringExtra(
                PackageInstaller.EXTRA_STATUS_MESSAGE
            )

            PackageEventStream.emit(
                mapOf(
                    "package" to pkg,
                    "action" to "uninstall",
                    "status" to "failure",
                    "message" to msg
                )
            )
        }
    }
}
