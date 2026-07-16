package com.sulav.sleepblock.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.sulav.sleepblock.blocking.SleepAppBlocking
import com.sulav.sleepblock.data.SleepStore
import com.sulav.sleepblock.ui.theme.NightBackground
import com.sulav.sleepblock.ui.theme.PrimaryButton
import com.sulav.sleepblock.ui.theme.SleepColors
import com.sulav.sleepblock.ui.theme.SleepType
import com.sulav.sleepblock.ui.theme.glassSurface

/**
 * The last gate before Main (the Android sibling of ios
 * ScreenTimePrimerView): SleepBlock is an app-blocking app, and this is
 * where blocking gets its teeth — asked at peak commitment, right after
 * onboarding, never mid-sign-up. Android needs two special grants (usage
 * access + display over other apps), each a trip into system Settings, so
 * the primer walks them as a checklist with live status. One-shot per
 * install; "Not now" always works — the Blocked apps screen stays the
 * fixup path — and nobody gets trapped at a gate.
 */
@Composable
fun BlockingPrimerScreen(store: SleepStore) {
    val context = LocalContext.current
    var revision by remember { mutableStateOf(0) }
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(lifecycleOwner) {
        lifecycleOwner.lifecycle.addObserver(
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) revision += 1
            }
        )
    }
    val hasUsage = remember(revision) { SleepAppBlocking.hasUsageAccess(context) }
    val hasOverlay = remember(revision) { SleepAppBlocking.hasOverlayPermission(context) }

    // Both granted: the primer's job is done the moment we're back.
    LaunchedEffect(hasUsage, hasOverlay) {
        if (hasUsage && hasOverlay) store.completeBlockingPrimer()
    }

    NightBackground {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 24.dp),
        ) {
            Spacer(Modifier.weight(1f))
            Text(
                "Let SleepBlock put your apps to sleep",
                style = SleepType.hero,
                fontSize = 30.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(12.dp))
            Text(
                "Two quick permissions make the lockdown real. Calls always work.",
                style = SleepType.body,
                color = SleepColors.dim,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(40.dp))
            Column(Modifier.fillMaxWidth().glassSurface().padding(horizontal = 20.dp)) {
                GrantRow(
                    icon = Icons.Default.Visibility,
                    title = "Usage access",
                    subtitle = "See which app opens at night",
                    granted = hasUsage,
                ) { context.startActivity(SleepAppBlocking.usageAccessSettingsIntent()) }
                HorizontalDivider(color = SleepColors.hairline)
                GrantRow(
                    icon = Icons.Default.Lock,
                    title = "Display over other apps",
                    subtitle = "Show the shield over a blocked app",
                    granted = hasOverlay,
                ) { context.startActivity(SleepAppBlocking.overlaySettingsIntent(context)) }
            }
            Spacer(Modifier.weight(1f))
            PrimaryButton(
                if (!hasUsage) "Turn on app blocking" else "Almost there — one more",
            ) {
                context.startActivity(
                    if (!hasUsage) SleepAppBlocking.usageAccessSettingsIntent()
                    else SleepAppBlocking.overlaySettingsIntent(context)
                )
            }
            Spacer(Modifier.height(16.dp))
            Text(
                "Not now",
                style = SleepType.body,
                color = SleepColors.dim,
                modifier = Modifier
                    .clickable { store.completeBlockingPrimer() }
                    .padding(12.dp),
            )
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun GrantRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    granted: Boolean,
    onClick: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !granted, onClick = onClick)
            .padding(vertical = 16.dp),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(40.dp)
                .background(SleepColors.amber.copy(alpha = 0.14f), RoundedCornerShape(12.dp)),
        ) {
            Icon(icon, null, tint = SleepColors.amber, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.size(16.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = SleepType.body)
            Text(subtitle, style = SleepType.body, fontSize = 13.sp, color = SleepColors.muted)
        }
        if (granted) {
            Icon(Icons.Default.Check, null, tint = SleepColors.gold, modifier = Modifier.size(22.dp))
        } else {
            Text("Grant", style = SleepType.body, color = SleepColors.amber)
        }
    }
}
