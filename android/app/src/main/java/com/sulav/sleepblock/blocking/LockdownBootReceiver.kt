package com.sulav.sleepblock.blocking

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.sulav.sleepblock.data.SleepPersistence

/**
 * Resumes the night watch after a reboot (or an app update — my own
 * package replacement force-stops the service, exactly the hole a
 * mid-night OTA would leave). A sleep session lives in persistence, so if
 * one is still active when the device comes back, the lockdown should too.
 */
class LockdownBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val persistence = SleepPersistence(context)
        val sessionActive = persistence.activeSession != null
        val hasSelection = persistence.blockedPackages.isNotEmpty()
        val blockingOn = persistence.profile?.blockDuringSleep ?: true
        if (sessionActive && blockingOn && hasSelection &&
            SleepAppBlocking.hasUsageAccess(context) &&
            SleepAppBlocking.hasOverlayPermission(context)
        ) {
            Log.i("SleepLockdown", "Resuming lockdown after $action")
            SleepLockdownService.start(context)
        }
    }
}
