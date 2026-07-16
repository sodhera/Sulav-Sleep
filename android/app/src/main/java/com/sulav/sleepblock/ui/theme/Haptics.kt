package com.sulav.sleepblock.ui.theme

import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView

/**
 * The app's haptic voice (mirrors ios Haptics): deliberately strong — every
 * button fires a knock, wired centrally into the shared components so call
 * sites can't forget it. Ticks survive for non-button cues (wheel detents,
 * the slide rail's ratchet), and success marks a night logged.
 */
class Haptics(private val view: View) {
    /** The single heavy knock every button fires. */
    fun knock() {
        view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
    }

    /** Light detent for wheels and drag ratchets. */
    fun tick() {
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    }

    /** The strongest cue, reserved for commitment moments. */
    fun heavy() {
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    }

    /** A night beginning or ending. */
    fun success() {
        view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
    }
}

@Composable
fun rememberHaptics(): Haptics {
    val view = LocalView.current
    return remember(view) { Haptics(view) }
}
