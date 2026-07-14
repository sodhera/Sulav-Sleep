package com.sulav.sleepblock.ui.sleep

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sulav.sleepblock.data.SleepFormatting
import com.sulav.sleepblock.data.SleepStore
import com.sulav.sleepblock.ui.theme.SectionLabel
import com.sulav.sleepblock.ui.theme.SleepColors
import com.sulav.sleepblock.ui.theme.SleepType
import kotlinx.coroutines.delay

/**
 * Active sleep — true OLED black, only ember pixels lit (mirrors ios
 * SleepModeView). Deliberate exits are held, harmless returns are taps:
 * Hold to wake (1.2s), Back to sleep (tap), Hold to cancel (0.8s, logs no
 * night). Tapping the dark toggles the controls in and out.
 */
@Composable
fun SleepModeScreen(store: SleepStore) {
    val active = store.activeSession ?: return
    var controlsVisible by remember { mutableStateOf(false) }

    // Elapsed timer ticking every second.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1_000)
            now = System.currentTimeMillis()
        }
    }
    val elapsedSeconds = ((now - active.start.toEpochMilli()) / 1000).coerceAtLeast(0)
    val h = elapsedSeconds / 3600
    val m = (elapsedSeconds % 3600) / 60
    val s = elapsedSeconds % 60

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { controlsVisible = !controlsVisible },
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 24.dp),
        ) {
            Spacer(Modifier.weight(1f))
            // Ember only on OLED black — never a platform-colored emoji.
            Icon(
                Icons.Default.DarkMode,
                contentDescription = null,
                tint = SleepColors.emberDim,
                modifier = Modifier.size(56.dp),
            )
            Spacer(Modifier.height(24.dp))
            SectionLabel("Asleep")
            Spacer(Modifier.height(8.dp))
            Text(
                String.format("%d:%02d:%02d", h, m, s),
                style = SleepType.hero,
                fontSize = 52.sp,
                color = SleepColors.ember,
            )
            store.profile?.let {
                Spacer(Modifier.height(8.dp))
                Text(
                    "wake ${SleepFormatting.clockTime(it.wakeTime)}",
                    style = SleepType.body,
                    color = SleepColors.emberDim,
                )
            }
            Spacer(Modifier.weight(1f))

            AnimatedVisibility(visible = controlsVisible, enter = fadeIn(), exit = fadeOut()) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    HoldButton(
                        label = "Hold to wake",
                        holdMillis = 1_200,
                        prominent = true,
                        onComplete = { store.wakeUp() },
                    )
                    Spacer(Modifier.height(16.dp))
                    Text(
                        "Back to sleep",
                        style = SleepType.body,
                        color = SleepColors.emberDim,
                        modifier = Modifier
                            .clickable { controlsVisible = false }
                            .padding(12.dp),
                    )
                    Spacer(Modifier.height(24.dp))
                    HoldButton(
                        label = "Hold to cancel",
                        holdMillis = 800,
                        prominent = false,
                        onComplete = { store.cancelSleep() },
                    )
                }
            }
            AnimatedVisibility(visible = !controlsVisible, enter = fadeIn(tween(900)), exit = fadeOut()) {
                Text(
                    "Tap to wake",
                    style = SleepType.body,
                    color = SleepColors.emberDim.copy(alpha = 0.6f),
                    textAlign = TextAlign.Center,
                )
            }
            Spacer(Modifier.height(48.dp))
        }
    }
}

/**
 * Press-and-hold capsule: an ember fill sweeps while held; releasing early
 * sighs back. No single tap can fire it.
 */
@Composable
private fun HoldButton(
    label: String,
    holdMillis: Int,
    prominent: Boolean,
    onComplete: () -> Unit,
) {
    var pressed by remember { mutableStateOf(false) }
    var completed by remember { mutableStateOf(false) }
    val progress by animateFloatAsState(
        targetValue = if (pressed) 1f else 0f,
        animationSpec = tween(if (pressed) holdMillis else 250),
        label = "hold",
        finishedListener = { value ->
            if (value >= 1f && pressed && !completed) {
                completed = true
                onComplete()
            }
        },
    )

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .then(if (prominent) Modifier.fillMaxWidth().height(58.dp) else Modifier.height(44.dp))
            .clip(CircleShape)
            .background(if (prominent) SleepColors.ember.copy(alpha = 0.15f) else Color.Transparent)
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        val down = awaitPointerEvent()
                        if (down.changes.any { it.pressed }) {
                            pressed = true
                            // Wait for release.
                            while (awaitPointerEvent().changes.any { it.pressed }) { /* held */ }
                            pressed = false
                            completed = false
                        }
                    }
                }
            },
    ) {
        // Ember fill sweeping left → right with hold progress.
        Box(Modifier.matchParentSize()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(progress.coerceAtLeast(0.001f))
                    .fillMaxHeight()
                    .background(SleepColors.ember.copy(alpha = if (prominent) 0.35f else 0.2f)),
            )
        }
        Text(
            label,
            style = SleepType.body,
            fontWeight = if (prominent) FontWeight.SemiBold else FontWeight.Normal,
            color = if (prominent) SleepColors.ember else SleepColors.emberDim,
            modifier = Modifier.padding(horizontal = 32.dp),
        )
    }
}
