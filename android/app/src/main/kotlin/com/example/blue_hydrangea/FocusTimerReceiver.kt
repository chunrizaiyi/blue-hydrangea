package com.example.blue_hydrangea

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Receives the exact deadline even while the app process or display is asleep. */
class FocusTimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            FocusTimerService.actionExpire -> FocusTimerService.expireFromSystem(
                context,
                intent.getStringExtra(FocusTimerService.extraSessionId),
            )
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED ->
                FocusTimerService.restoreAfterSystemEvent(context)
        }
    }
}
