package com.sulav.sleepblock.data

import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Mirror of ios/SulavSleep/SleepFormatting.swift. */
object SleepFormatting {

    private val timeFormatter = DateTimeFormatter.ofPattern("h:mm a", Locale.US)
    private val dayFormatter = DateTimeFormatter.ofPattern("EEE, MMM d", Locale.US)

    /** Minutes-from-midnight → "10:30 PM". */
    fun clockTime(minutes: Int): String =
        LocalTime.of((minutes / 60) % 24, minutes % 60).format(timeFormatter)

    /** 440 → "7h 20m". */
    fun duration(minutes: Int): String {
        val h = minutes / 60
        val m = minutes % 60
        return when {
            h == 0 -> "${m}m"
            m == 0 -> "${h}h"
            else -> "${h}h ${m}m"
        }
    }

    fun dayLabel(instant: Instant): String =
        instant.atZone(ZoneId.systemDefault()).format(dayFormatter)

    /** Same hour bands as the iOS greeting (and CityPhase). */
    fun greeting(hour: Int = LocalTime.now().hour): String = when (hour) {
        in 5..11 -> "Good morning"
        in 12..16 -> "Good afternoon"
        in 17..21 -> "Good evening"
        else -> "Time for bed"
    }

    /** Minutes from now until the next occurrence of a minutes-from-midnight target. */
    fun minutesUntil(target: Int, now: LocalTime = LocalTime.now()): Int {
        val current = now.hour * 60 + now.minute
        var diff = target - current
        if (diff < 0) diff += 1_440
        return diff
    }
}
