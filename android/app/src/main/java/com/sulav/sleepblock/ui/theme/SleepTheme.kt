package com.sulav.sleepblock.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Warm Pixel Night, Android edition (see DESIGN.md). iOS renders its chrome
 * in Liquid Glass; Android uses the sanctioned fallback grammar — translucent
 * deep-navy surfaces with hairline borders — over the widgets' minimal night
 * gradient (the pixel-art scene port is phase 2).
 */
object SleepColors {
    val background = Color(0xFF08111E)
    val skyTop = Color(0xFF152238)
    val navy = Color(0xFF111827)
    val card = Color(0xFF18212F)
    val amber = Color(0xFFF4A261)
    val gold = Color(0xFFE9C46A)
    val danger = Color(0xFFD96C75)
    val ink = Color(0xFFF5F5F2)
    val dim = Color(0xFFB7BDC7)
    val muted = Color(0xFF7A8795)
    val hairline = Color.White.copy(alpha = 0.06f)
    val border = Color.White.copy(alpha = 0.05f)
    val glass = Color.White.copy(alpha = 0.06f)
    val ember = Color(0xFFE0854E)
    val emberDim = Color(0xFF9C5A36)
}

object SleepType {
    val hero = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 40.sp, color = SleepColors.ink)
    val title = TextStyle(fontWeight = FontWeight.Medium, fontSize = 24.sp, color = SleepColors.ink)
    val body = TextStyle(fontWeight = FontWeight.Normal, fontSize = 16.sp, lineHeight = 25.sp, color = SleepColors.ink)
    val label = TextStyle(fontWeight = FontWeight.Medium, fontSize = 12.sp, letterSpacing = 2.4.sp, color = SleepColors.muted)
}

private val NightColorScheme = darkColorScheme(
    primary = SleepColors.amber,
    onPrimary = SleepColors.navy,
    secondary = SleepColors.gold,
    background = SleepColors.background,
    onBackground = SleepColors.ink,
    surface = SleepColors.navy,
    onSurface = SleepColors.ink,
    error = SleepColors.danger,
)

@Composable
fun SleepBlockTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = NightColorScheme, content = content)
}

/** The minimal night gradient with a faint amber floor glow. */
@Composable
fun NightBackground(content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(SleepColors.skyTop, SleepColors.background)))
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0f to Color.Transparent,
                        0.75f to Color.Transparent,
                        1f to SleepColors.amber.copy(alpha = 0.08f),
                    )
                )
        )
        content()
    }
}

/** Small-caps section kicker (the app's one section-label grammar). */
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(text.uppercase(), style = SleepType.label, modifier = modifier)
}

/** Amber primary action capsule — the brightest control on any screen. */
@Composable
fun PrimaryButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = SleepColors.amber,
            contentColor = SleepColors.navy,
            disabledContainerColor = SleepColors.amber.copy(alpha = 0.3f),
            disabledContentColor = SleepColors.navy.copy(alpha = 0.5f),
        ),
        modifier = modifier.fillMaxWidth().height(58.dp),
    ) {
        Text(text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** Quiet untinted sibling of [PrimaryButton]. */
@Composable
fun SecondaryButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = SleepColors.glass,
            contentColor = SleepColors.ink,
            disabledContainerColor = SleepColors.glass,
            disabledContentColor = SleepColors.muted,
        ),
        modifier = modifier.fillMaxWidth().height(58.dp),
    ) {
        Text(text, fontSize = 17.sp, fontWeight = FontWeight.Medium)
    }
}

/** Translucent navy surface with a hairline border — the fallback "glass". */
fun Modifier.glassSurface(shape: RoundedCornerShape = RoundedCornerShape(20.dp)): Modifier =
    this
        .background(SleepColors.glass, shape)
        .border(1.dp, SleepColors.border, shape)
