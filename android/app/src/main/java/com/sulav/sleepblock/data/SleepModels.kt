package com.sulav.sleepblock.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.time.Instant

/**
 * Kotlin mirror of the iOS data model (ios/SulavSleep/SleepModels.swift).
 * Field names and JSON shapes match the iOS persistence so the two clients
 * stay conceptually one product; see docs/android.md.
 */

enum class AppTab { HOME, PROFILE }

@Serializable
data class Profile(
    val name: String,
    /** Target bedtime in minutes from midnight — what the countdown keys off. */
    val bedtime: Int,
    /** Target wake time in minutes from midnight. */
    val wakeTime: Int,
    val onboarded: Boolean,
    val blockDuringSleep: Boolean = true,
    val lockdownMaxHours: Int = 6,
    val sleepStruggles: List<String> = emptyList(),
    val timeSinkApps: List<String> = emptyList(),
    val primaryGoal: String = "",
    val lateNightPhone: String = "",
    val wakeFeeling: String = "",
)

/** Everything the sign-up questionnaire collects, in one piece. */
data class OnboardingAnswers(
    val name: String,
    val bedtime: Int,
    val wakeTime: Int,
    val struggles: List<String> = emptyList(),
    val timeSinks: List<String> = emptyList(),
    val goal: String = "",
    val lateNightPhone: String = "",
    val wakeFeeling: String = "",
)

enum class SleepStruggle(val raw: String, val title: String) {
    PHONE_IN_BED("phoneInBed", "Phone in bed"),
    FALLING_ASLEEP("fallingAsleep", "Trouble falling asleep"),
    WAKING_AT_NIGHT("wakingAtNight", "Waking up at night"),
    INCONSISTENT_SCHEDULE("inconsistentSchedule", "Inconsistent schedule"),
    WAKING_TIRED("wakingTired", "Waking up tired"),
}

enum class TimeSinkApp(val raw: String, val title: String) {
    INSTAGRAM("instagram", "Instagram"),
    TIKTOK("tiktok", "TikTok"),
    YOUTUBE("youtube", "YouTube"),
    X("x", "X"),
    REDDIT("reddit", "Reddit"),
    SNAPCHAT("snapchat", "Snapchat"),
    GAMES("games", "Games"),
    OTHER("other", "Other"),
}

enum class SleepGoal(val raw: String, val title: String) {
    FALL_ASLEEP_EARLIER("fallAsleepEarlier", "Fall asleep earlier"),
    WAKE_UP_RESTED("wakeUpRested", "Wake up with more energy"),
    LESS_PHONE_AT_NIGHT("lessPhoneAtNight", "Break the late-night phone habit"),
    CONSISTENT_SCHEDULE("consistentSchedule", "Keep a consistent schedule"),
}

enum class LateNightPhoneTime(val raw: String, val title: String, val nightlyMinutes: Int) {
    QUARTER_HOUR("quarterHour", "15 minutes or less", 15),
    HALF_HOUR("halfHour", "About 30 minutes", 30),
    HOUR("hour", "About an hour", 60),
    TWO_PLUS("twoPlus", "2 hours or more", 120);

    val weeklyMinutes: Int get() = nightlyMinutes * 7
}

enum class WakeFeeling(val raw: String, val title: String) {
    GROGGY("groggy", "Groggy"),
    TIRED("tired", "Still tired"),
    OKAY("okay", "Okay"),
    RESTED("rested", "Rested"),
}

@Serializable
enum class SleepSource {
    @SerialName("local") LOCAL,
    @SerialName("healthKit") HEALTH,
}

/** ISO-8601 Instant, matching the iOS JSON date strategy. */
object InstantIso8601Serializer : KSerializer<Instant> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("Instant", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: Instant) =
        encoder.encodeString(value.toString())

    override fun deserialize(decoder: Decoder): Instant =
        Instant.parse(decoder.decodeString())
}

@Serializable
data class SleepSession(
    val id: String,
    @Serializable(with = InstantIso8601Serializer::class) val start: Instant,
    @Serializable(with = InstantIso8601Serializer::class) val end: Instant,
    val durationMinutes: Int,
    val source: SleepSource = SleepSource.LOCAL,
)

@Serializable
data class ActiveSleepSession(
    @Serializable(with = InstantIso8601Serializer::class) val start: Instant,
)

object SleepMath {
    /** Minutes between bedtime and wake, wrapping past midnight. */
    fun windowMinutes(bedtime: Int, wakeTime: Int): Int {
        var diff = wakeTime - bedtime
        if (diff <= 0) diff += 1_440
        return diff
    }
}
