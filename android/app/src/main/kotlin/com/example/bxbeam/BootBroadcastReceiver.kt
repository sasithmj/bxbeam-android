package com.example.bxbeam

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d("BootBroadcastReceiver", "Received intent action: $action")
        
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_USER_PRESENT ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON") {
            
            Log.d("BootBroadcastReceiver", "Launching MainActivity...")
            
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            context.startActivity(launchIntent)
        }
    }
}
