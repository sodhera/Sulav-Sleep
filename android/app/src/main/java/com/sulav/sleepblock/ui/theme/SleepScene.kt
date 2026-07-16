package com.sulav.sleepblock.ui.theme

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import com.sulav.sleepblock.R
import java.time.LocalTime
import kotlinx.coroutines.delay

/**
 * The living pixel city (port of ios SleepBackground.swift): real depth
 * planes — a static sky, drifting clouds, and four skylines each slightly
 * oversized and independently drifting (the sky barely, the front most).
 * The city follows the user's day (day 5–17, dusk 17–22, night 22–5, the
 * same bands as the greeting copy), crossfading at the boundary. A
 * readability scrim sits between the scene and the content: clear through
 * the upper sky, deep navy by the bottom where text lives; day and dusk
 * get a fuller veil since the ink system was designed against a dark
 * night stage. Motion is ambient — if you notice it, it's too strong.
 */
enum class CityPhase { DAY, DUSK, NIGHT }

fun cityPhase(hour: Int = LocalTime.now().hour): CityPhase = when (hour) {
    in 5..16 -> CityPhase.DAY
    in 17..21 -> CityPhase.DUSK
    else -> CityPhase.NIGHT
}

@Composable
fun NightBackground(content: @Composable () -> Unit) {
    var phase by remember { mutableStateOf(cityPhase()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000)
            phase = cityPhase()
        }
    }

    Box(Modifier.fillMaxSize().background(SleepColors.background)) {
        Crossfade(targetState = phase, label = "cityPhase") { current ->
            SceneLayers(current)
        }
        // Readability scrim: atmospheric haze, never a card. Day/dusk veil
        // the full height; night keeps its clear upper sky.
        val scrim = when (phase) {
            CityPhase.NIGHT -> Brush.verticalGradient(
                0f to Color.Transparent,
                0.45f to SleepColors.background.copy(alpha = 0.35f),
                1f to SleepColors.background.copy(alpha = 0.82f),
            )
            else -> Brush.verticalGradient(
                0f to SleepColors.background.copy(alpha = 0.30f),
                0.5f to SleepColors.background.copy(alpha = 0.55f),
                1f to SleepColors.background.copy(alpha = 0.85f),
            )
        }
        Box(Modifier.fillMaxSize().background(scrim))
        content()
    }
}

@Composable
private fun SceneLayers(phase: CityPhase) {
    val slug = when (phase) {
        CityPhase.DAY -> "day"
        CityPhase.DUSK -> "dusk"
        CityPhase.NIGHT -> "night"
    }
    val context = androidx.compose.ui.platform.LocalContext.current
    val ids = remember(slug) {
        listOf("sky", "clouds", "far", "mid", "near", "front").map { layer ->
            context.resources.getIdentifier("city_${slug}_$layer", "drawable", context.packageName)
        }
    }

    val drift = rememberInfiniteTransition(label = "drift")
    // One shared 0→1 phase; each plane maps it to its own tiny travel so
    // the parallax stays coherent (a slow ping-pong nobody consciously sees).
    val t by drift.animateFloat(
        initialValue = -1f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 90_000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "t",
    )

    // Travel in px per plane: sky static, clouds and skylines increasing.
    val travels = listOf(0f, 26f, 10f, 18f, 30f, 44f)
    ids.forEachIndexed { index, resId ->
        if (resId == 0) return@forEachIndexed
        val bitmap = ImageBitmap.imageResource(resId)
        Image(
            // Nearest-neighbor keeps the pixel art crisp at any scale.
            painter = remember(resId) { BitmapPainter(bitmap, filterQuality = FilterQuality.None) },
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    // Slight oversize gives the drift somewhere to go.
                    scaleX = 1.12f
                    scaleY = 1.12f
                    translationX = t * travels[index]
                },
        )
    }
}
