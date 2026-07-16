package com.sulav.sleepblock.ui.theme

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sulav.sleepblock.R

/**
 * The brand mark alive (port of the iOS SlothBrandMark): the sleeping sloth
 * with a chain of gold z's rising off its head — each z drifts up the same
 * diagonal, swells a touch, and fades before the next follows, quieter than
 * any nearby numerals so it reads as breathing, not motion. Decorative only.
 */
@Composable
fun SlothBrandMark(modifier: Modifier = Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Image(
            painter = painterResource(R.drawable.sloth_brand),
            contentDescription = null,
            modifier = Modifier.fillMaxWidth(),
        )
        RisingZs(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .offset(x = (-8).dp, y = (-6).dp),
        )
    }
}

/** Three staggered z's on one shared 7.5s-feel cycle. */
@Composable
fun RisingZs(modifier: Modifier = Modifier) {
    Box(modifier) {
        listOf(0, 1, 2).forEach { index ->
            RisingZ(index)
        }
    }
}

@Composable
private fun RisingZ(index: Int) {
    val transition = rememberInfiniteTransition(label = "z$index")
    val cycle = 2_500
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(cycle * 3, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
            initialStartOffset = StartOffset(index * cycle),
        ),
        label = "p",
    )
    // Each z lives in the first third of its own staggered cycle.
    val local = (progress * 3f).coerceIn(0f, 1f)
    val alpha = when {
        local < 0.2f -> local / 0.2f
        local > 0.8f -> (1f - local) / 0.2f
        else -> 1f
    }
    Text(
        "z",
        color = SleepColors.gold,
        fontSize = (14 + index * 3).sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.graphicsLayer {
            // Up the shared diagonal, swelling slightly as it climbs.
            translationX = local * 26f + index * 12f
            translationY = -local * 40f - index * 16f
            scaleX = 0.8f + local * 0.35f
            scaleY = 0.8f + local * 0.35f
            this.alpha = alpha * 0.9f
        },
    )
}
