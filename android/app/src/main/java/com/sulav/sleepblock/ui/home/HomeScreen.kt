package com.sulav.sleepblock.ui.home

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sulav.sleepblock.data.SleepFormatting
import com.sulav.sleepblock.data.SleepMath
import com.sulav.sleepblock.data.SleepStore
import com.sulav.sleepblock.ui.theme.PrimaryButton
import com.sulav.sleepblock.ui.theme.SectionLabel
import com.sulav.sleepblock.ui.theme.SleepColors
import com.sulav.sleepblock.ui.theme.SleepType
import com.sulav.sleepblock.ui.theme.glassSurface
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

/**
 * Home — a near-wordless "go to bed" screen (mirrors ios HomeView), with the
 * slide-to-sleep confirmation scrolling up over it (SleepConfirmationPanel).
 */
@Composable
fun HomeScreen(store: SleepStore) {
    AnimatedContent(
        targetState = store.showSleepConfirmation,
        transitionSpec = {
            if (targetState) {
                (slideInVertically { it } + fadeIn()) togetherWith (slideOutVertically { -it / 3 } + fadeOut())
            } else {
                (slideInVertically { -it / 3 } + fadeIn()) togetherWith (slideOutVertically { it } + fadeOut())
            }
        },
        label = "home",
    ) { confirming ->
        if (confirming) {
            SleepConfirmationPanel(store)
        } else {
            HomeBody(store)
        }
    }
}

@Composable
private fun HomeBody(store: SleepStore) {
    val profile = store.profile ?: return
    // Re-derive the countdown every 30s so it ticks without user input.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            now = System.currentTimeMillis()
        }
    }
    val minutesToBed = remember(now, profile.bedtime) { SleepFormatting.minutesUntil(profile.bedtime) }
    // For a few hours past bedtime the countdown gives way to a wind-down nudge
    // rather than counting 20-odd hours to tomorrow's bedtime.
    val pastBedtime = minutesToBed > 20 * 60

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 24.dp),
    ) {
        Spacer(Modifier.weight(1f))
        SectionLabel(SleepFormatting.greeting())
        Spacer(Modifier.height(4.dp))
        Text(profile.name, style = SleepType.hero)
        Spacer(Modifier.height(40.dp))
        if (pastBedtime) {
            Text("Wind down", style = SleepType.title, color = SleepColors.amber)
            Text("It's past your bedtime", style = SleepType.body, color = SleepColors.dim)
        } else {
            SectionLabel("Bedtime in")
            Spacer(Modifier.height(4.dp))
            Text(
                "${minutesToBed / 60}h ${minutesToBed % 60}m",
                style = SleepType.hero,
                fontSize = 48.sp,
                color = SleepColors.gold,
            )
        }
        Spacer(Modifier.height(24.dp))
        // Tonight's window as the single fact it is: moon bedtime → sun wake.
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .glassSurface(RoundedCornerShape(24.dp))
                .padding(horizontal = 20.dp, vertical = 10.dp),
        ) {
            Icon(Icons.Default.DarkMode, null, tint = SleepColors.amber, modifier = Modifier.size(16.dp))
            Text(SleepFormatting.clockTime(profile.bedtime), style = SleepType.body)
            Text("→", style = SleepType.body, color = SleepColors.muted)
            Icon(Icons.Default.WbSunny, null, tint = SleepColors.gold, modifier = Modifier.size(16.dp))
            Text(SleepFormatting.clockTime(profile.wakeTime), style = SleepType.body)
        }
        Spacer(Modifier.weight(1f))
        PrimaryButton("Sleep Now") { store.showSleepConfirmation = true }
        Spacer(Modifier.height(16.dp))
        // Last night as one quiet centered strip — only when it honestly is
        // last night; a stale record renders nothing at all.
        store.lastNightSession?.let { night ->
            Text(
                "Last night ${SleepFormatting.duration(night.durationMinutes)}" +
                    if (store.onTrackStreak > 0) " · 🔥${store.onTrackStreak}" else "",
                style = SleepType.body,
                color = SleepColors.dim,
                textAlign = TextAlign.Center,
            )
        }
        Spacer(Modifier.height(64.dp))
    }
}

// MARK: - Confirmation panel

@Composable
private fun SleepConfirmationPanel(store: SleepStore) {
    val profile = store.profile ?: return
    val back: () -> Unit = { store.showSleepConfirmation = false }
    BackHandler(onBack = back)

    // The sleep you'd get sliding now, until the scheduled wake time.
    val nowMinutes = remember {
        val t = java.time.LocalTime.now()
        t.hour * 60 + t.minute
    }
    val sleepMinutes = SleepMath.windowMinutes(nowMinutes, profile.wakeTime)

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 24.dp),
    ) {
        Spacer(Modifier.weight(1f))
        SectionLabel("Tonight")
        Spacer(Modifier.height(8.dp))
        Text(
            "${sleepMinutes / 60}h ${sleepMinutes % 60}m",
            style = SleepType.hero,
            fontSize = 56.sp,
            color = SleepColors.gold,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            "of sleep · wake ${SleepFormatting.clockTime(profile.wakeTime)}",
            style = SleepType.body,
            color = SleepColors.dim,
        )
        Spacer(Modifier.height(24.dp))
        // App blocking is Android phase 2, so tonight's lockdown row states
        // the honest fact: nothing is blocked yet.
        Text("No apps blocked tonight", style = SleepType.body, color = SleepColors.muted)
        Spacer(Modifier.weight(1f))
        SlideToSleep(onComplete = { store.startSleep() })
        Spacer(Modifier.height(16.dp))
        Text(
            "Cancel",
            style = SleepType.body,
            color = SleepColors.dim,
            modifier = Modifier
                .clickable(onClick = back)
                .padding(8.dp),
        )
        Spacer(Modifier.height(40.dp))
    }
}

/**
 * The iPhone-style slide-to-sleep rail: a near-solid navy track rimmed in
 * amber, a draggable amber knob, releasing short springs back. Sliding the
 * knob across the full track is the only way a night begins.
 */
@Composable
private fun SlideToSleep(onComplete: () -> Unit) {
    val trackHeight = 72.dp
    val knobSize = 60.dp
    val padding = 6.dp
    var trackWidthPx by remember { mutableFloatStateOf(0f) }
    var offsetPx by remember { mutableFloatStateOf(0f) }
    val density = LocalDensity.current
    val knobPx = with(density) { knobSize.toPx() }
    val paddingPx = with(density) { padding.toPx() }
    val maxOffset = (trackWidthPx - knobPx - paddingPx * 2).coerceAtLeast(1f)
    val progress = (offsetPx / maxOffset).coerceIn(0f, 1f)

    val drag = rememberDraggableState { delta ->
        offsetPx = (offsetPx + delta).coerceIn(0f, maxOffset)
    }

    Box(
        contentAlignment = Alignment.CenterStart,
        modifier = Modifier
            .fillMaxWidth()
            .height(trackHeight)
            .clip(CircleShape)
            .background(SleepColors.navy.copy(alpha = 0.9f))
            // The warm amber rim that keeps the rail the brightest control.
            .border(2.dp, SleepColors.amber.copy(alpha = 0.5f), CircleShape)
            .onSizeChanged { trackWidthPx = it.width.toFloat() }
            .draggable(
                state = drag,
                orientation = Orientation.Horizontal,
                onDragStopped = {
                    if (progress >= 0.97f) {
                        onComplete()
                    }
                    offsetPx = 0f
                },
            ),
    ) {
        // Hint fades as the knob travels.
        Text(
            "Slide to sleep",
            style = SleepType.body,
            color = SleepColors.ink.copy(alpha = (1f - progress * 1.6f).coerceIn(0f, 1f)),
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .padding(start = padding)
                .offset { IntOffset(offsetPx.roundToInt(), 0) }
                .size(knobSize)
                .background(
                    Brush.linearGradient(listOf(SleepColors.amber, SleepColors.gold)),
                    CircleShape,
                ),
        ) {
            Icon(
                Icons.Default.DarkMode,
                contentDescription = "Slide to sleep",
                tint = SleepColors.navy,
            )
        }
    }
}
