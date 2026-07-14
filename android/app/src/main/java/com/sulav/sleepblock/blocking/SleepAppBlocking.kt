package com.sulav.sleepblock.blocking

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Process
import android.provider.Settings

/**
 * Android's stand-in for iOS Screen Time (SleepScreenTime.swift). There is
 * no shield API here; blocking is usage-access polling (who's in the
 * foreground?) plus a full-screen shield the app itself presents. Two
 * user-granted special permissions make that possible:
 *
 * - **Usage access** (PACKAGE_USAGE_STATS): lets the lockdown service see
 *   which app came to the foreground.
 * - **Display over other apps** (SYSTEM_ALERT_WINDOW): lets the service put
 *   the shield on screen from the background (holding it exempts the app
 *   from background-activity-launch restrictions).
 *
 * Both live in system Settings, so the Blocked apps screen deep-links there.
 * Authorization is always read live — never persisted — mirroring the iOS
 * rule that a stale stored flag can never contradict reality.
 */
object SleepAppBlocking {

    fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun hasOverlayPermission(context: Context): Boolean =
        Settings.canDrawOverlays(context)

    fun usageAccessSettingsIntent(): Intent =
        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)

    fun overlaySettingsIntent(context: Context): Intent =
        Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${context.packageName}"),
        )

    /** A launchable app the user can choose to block. */
    data class InstalledApp(val packageName: String, val label: String, val icon: Drawable)

    /**
     * Every launcher-visible app except ourselves, alphabetical. Uses the
     * manifest `<queries>` launcher-intent filter, not QUERY_ALL_PACKAGES.
     */
    fun installedApps(context: Context): List<InstalledApp> {
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcher, 0)
            .mapNotNull { info ->
                val pkg = info.activityInfo.packageName
                if (pkg == context.packageName) return@mapNotNull null
                InstalledApp(
                    packageName = pkg,
                    label = info.loadLabel(pm).toString(),
                    icon = info.loadIcon(pm),
                )
            }
            .distinctBy { it.packageName }
            .sortedBy { it.label.lowercase() }
    }
}
