package com.sulav.sleepblock.blocking

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import com.sulav.sleepblock.MainActivity
import com.sulav.sleepblock.R
import com.sulav.sleepblock.data.SleepPersistence
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * The night watch: a foreground service that runs only while a sleep
 * session is active. Every second it asks UsageStats which app most
 * recently came to the foreground; if that app is on the blocked list, the
 * shield ([ShieldActivity]) is put on screen. The Android analog of the
 * iOS Screen Time shield, minus the OS enforcement — see docs/android.md
 * for the honest limitations.
 */
class SleepLockdownService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var blocked: Set<String> = emptySet()
    private var lastShieldAt = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        blocked = SleepPersistence(this).blockedPackages
        startForeground(NOTIFICATION_ID, buildNotification())
        if (blocked.isEmpty() || !SleepAppBlocking.hasUsageAccess(this)) {
            Log.w(TAG, "Nothing to guard (no selection or no usage access) — stopping")
            stopSelf()
            return START_NOT_STICKY
        }
        Log.i(TAG, "Lockdown started for ${blocked.size} app(s)")
        scope.launch { watch() }
        return START_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        Log.i(TAG, "Lockdown ended")
        super.onDestroy()
    }

    private suspend fun watch() {
        val usage = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        // Start the window a minute back so an already-open blocked app is
        // caught immediately, not only on its next foreground transition.
        var since = System.currentTimeMillis() - 60_000
        var foreground: String? = null
        while (scope.isActive) {
            val now = System.currentTimeMillis()
            val events = usage.queryEvents(since, now)
            val event = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) {
                    foreground = event.packageName
                }
            }
            since = now
            val current = foreground
            if (current != null && current in blocked && current != packageName) {
                // Debounce: the shield needs a beat to reach the foreground.
                if (now - lastShieldAt > 2_000) {
                    lastShieldAt = now
                    showShield(current)
                }
            }
            delay(1_000)
        }
    }

    private fun showShield(blockedPackage: String) {
        Log.i(TAG, "Shielding $blockedPackage")
        val intent = Intent(this, ShieldActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        // Launching from a service is allowed because the app holds
        // SYSTEM_ALERT_WINDOW (the overlay permission the setup flow asks for).
        startActivity(intent)
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Sleep lockdown",
                NotificationManager.IMPORTANCE_MIN,
            ).apply { description = "Shown quietly while your apps are asleep." }
        )
        val tap = android.app.PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            android.app.PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_moon)
            .setContentTitle("Your apps are asleep")
            .setContentText("SleepBlock is guarding the night. Calls always work.")
            .setOngoing(true)
            .setContentIntent(tap)
            .build()
    }

    companion object {
        private const val TAG = "SleepLockdown"
        private const val CHANNEL_ID = "sleep_lockdown"
        private const val NOTIFICATION_ID = 41

        fun start(context: Context) {
            context.startForegroundService(Intent(context, SleepLockdownService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SleepLockdownService::class.java))
        }
    }
}
