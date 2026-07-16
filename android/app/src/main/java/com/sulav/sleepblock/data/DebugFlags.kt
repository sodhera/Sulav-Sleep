package com.sulav.sleepblock.data

import android.content.Intent
import com.sulav.sleepblock.BuildConfig

/**
 * Debug-only review switches, the Android sibling of the iOS `-review-*`
 * launch arguments: they render gated surfaces deterministically on an
 * unconfigured build so they can be previewed and screenshotted.
 *
 *   adb shell am start -n com.sulav.sleepblock/.MainActivity --ez review-paywall true
 *   adb shell am start -n com.sulav.sleepblock/.MainActivity --ez review-subscription true
 *
 * No-ops on release builds.
 */
object DebugFlags {
    var reviewPaywall = false
        private set
    var reviewSubscription = false
        private set

    fun readFrom(intent: Intent?) {
        if (!BuildConfig.DEBUG || intent == null) return
        if (intent.getBooleanExtra("review-paywall", false)) reviewPaywall = true
        if (intent.getBooleanExtra("review-subscription", false)) reviewSubscription = true
    }
}
