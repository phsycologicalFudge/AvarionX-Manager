package com.example.colourswift_manager

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status =
            intent.getIntExtra("android.content.pm.extra.STATUS", -1)

        val message =
            intent.getStringExtra("android.content.pm.extra.STATUS_MESSAGE")

        Log.d("ShizukuInstall", "Status=$status Message=$message")
    }
}
