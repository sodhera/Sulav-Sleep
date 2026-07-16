package com.sulav.sleepblock.ui.theme

import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs

/**
 * The iOS-style scrollable time wheel: hour / minute / AM–PM columns that
 * snap to the row under the center band. The center band is the app's
 * fallback glass; the selected values read gold, neighbors fade with
 * distance. Reports interaction so the questionnaire can hold Next until
 * the user has actually touched the schedule.
 */
@Composable
fun WheelTimePicker(
    minutes: Int,
    onChange: (Int) -> Unit,
    onInteracted: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val hour24 = minutes / 60
    val initialHour12 = ((hour24 + 11) % 12)          // 0-based: 0 -> "1" … 11 -> "12"
    val initialMinuteIndex = (minutes % 60) / 5
    val initialPeriod = if (hour24 < 12) 0 else 1

    val hours = remember { (1..12).map { it.toString() } }
    val minuteSteps = remember { (0..55 step 5).map { "%02d".format(it) } }
    val periods = remember { listOf("AM", "PM") }

    val hourState = rememberLazyListState(initialHour12)
    val minuteState = rememberLazyListState(initialMinuteIndex)
    val periodState = rememberLazyListState(initialPeriod)

    // Recompute minutes-from-midnight whenever any column settles.
    val selection by remember {
        derivedStateOf {
            Triple(
                centeredIndex(hourState),
                centeredIndex(minuteState),
                centeredIndex(periodState),
            )
        }
    }
    LaunchedEffect(selection) {
        val (hourIndex, minuteIndex, periodIndex) = selection
        val hour12 = hourIndex + 1
        val h24 = (hour12 % 12) + if (periodIndex == 1) 12 else 0
        onChange(h24 * 60 + minuteIndex * 5)
    }
    // Any scroll on any column counts as touching the schedule.
    LaunchedEffect(
        hourState.isScrollInProgress,
        minuteState.isScrollInProgress,
        periodState.isScrollInProgress,
    ) {
        if (hourState.isScrollInProgress || minuteState.isScrollInProgress || periodState.isScrollInProgress) {
            onInteracted()
        }
    }

    Box(modifier = modifier.fillMaxWidth().height(WHEEL_HEIGHT), contentAlignment = Alignment.Center) {
        // The center selection band, under the numerals.
        Box(
            Modifier
                .fillMaxWidth(0.8f)
                .height(ROW_HEIGHT)
                .glassSurface(RoundedCornerShape(16.dp)),
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            WheelColumn(hours, hourState, width = 64.dp)
            Text(":", style = SleepType.title, color = SleepColors.muted)
            WheelColumn(minuteSteps, minuteState, width = 64.dp)
            Spacer(Modifier.width(12.dp))
            WheelColumn(periods, periodState, width = 64.dp)
        }
    }
}

private val ROW_HEIGHT = 44.dp
private val WHEEL_HEIGHT = ROW_HEIGHT * 5

private fun centeredIndex(state: LazyListState): Int {
    val info = state.layoutInfo
    if (info.visibleItemsInfo.isEmpty()) return 0
    val center = (info.viewportStartOffset + info.viewportEndOffset) / 2
    return info.visibleItemsInfo.minByOrNull { abs((it.offset + it.size / 2) - center) }?.index ?: 0
}

@Composable
private fun WheelColumn(items: List<String>, state: LazyListState, width: androidx.compose.ui.unit.Dp) {
    val flingBehavior = rememberSnapFlingBehavior(lazyListState = state)
    val centered by remember { derivedStateOf { centeredIndex(state) } }
    // Each detent under the center band ticks, like the iOS wheel.
    val haptics = rememberHaptics()
    LaunchedEffect(centered) {
        if (state.isScrollInProgress) haptics.tick()
    }
    LazyColumn(
        state = state,
        flingBehavior = flingBehavior,
        horizontalAlignment = Alignment.CenterHorizontally,
        // Two empty row-heights of padding let the first/last items reach center.
        contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = ROW_HEIGHT * 2),
        modifier = Modifier.width(width).height(WHEEL_HEIGHT),
    ) {
        items(items.size) { index ->
            val distance = abs(index - centered)
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.height(ROW_HEIGHT).fillMaxWidth(),
            ) {
                Text(
                    items[index],
                    fontSize = if (distance == 0) 26.sp else 20.sp,
                    fontWeight = if (distance == 0) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (distance == 0) SleepColors.gold else SleepColors.dim,
                    modifier = Modifier
                        .alpha(
                            when (distance) {
                                0 -> 1f
                                1 -> 0.5f
                                else -> 0.25f
                            }
                        )
                        .padding(horizontal = 4.dp),
                )
            }
        }
    }
}
