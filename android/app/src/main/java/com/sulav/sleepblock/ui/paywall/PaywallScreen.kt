package com.sulav.sleepblock.ui.paywall

import android.app.Activity
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.setValue
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sulav.sleepblock.R
import com.sulav.sleepblock.data.SleepStore
import com.sulav.sleepblock.subscription.SleepPlan
import com.sulav.sleepblock.ui.theme.NightBackground
import com.sulav.sleepblock.ui.theme.PrimaryButton
import com.sulav.sleepblock.ui.theme.SleepColors
import com.sulav.sleepblock.ui.theme.SleepType
import com.sulav.sleepblock.ui.theme.glassSurface
import kotlinx.coroutines.launch

/**
 * The hard paywall (mirrors ios PaywallView): appears once between the
 * account step and Main, only ever off a *resolved* not-entitled answer.
 * No ✕, no "not now" — softened by honesty: the CTA names the real trial,
 * annual preselected, failures in danger red, notices in calm amber.
 */
@Composable
fun PaywallScreen(store: SleepStore) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var plans by remember { mutableStateOf<List<SleepPlan>?>(null) }
    var loadFailed by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<SleepPlan?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var messageIsNotice by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var loadKey by remember { mutableStateOf(0) }

    LaunchedEffect(loadKey) {
        loadFailed = false
        plans = null
        val fetched = store.fetchPlans()
        if (fetched.isEmpty()) {
            loadFailed = true
        } else {
            plans = fetched
            selected = fetched.firstOrNull { it.isAnnual } ?: fetched.first()
        }
    }

    NightBackground {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 24.dp),
        ) {
            Spacer(Modifier.weight(1f))
            Image(
                painter = painterResource(R.drawable.sloth_brand),
                contentDescription = null,
                modifier = Modifier.fillMaxWidth(0.4f),
            )
            Spacer(Modifier.height(8.dp))
            Text("SLEEPBLOCK", style = SleepType.label, color = SleepColors.dim)
            Spacer(Modifier.height(24.dp))
            val trialDays = selected?.trialDays ?: 0
            Text(
                if (trialDays > 0) "Start your $trialDays-nights FREE trial to continue"
                else "Unlock SleepBlock to build a sleep routine that sticks",
                style = SleepType.hero,
                fontSize = 28.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.weight(1f))

            when {
                loadFailed -> {
                    Text("Couldn't load plans.", style = SleepType.body, color = SleepColors.dim)
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "Try again",
                        style = SleepType.body,
                        color = SleepColors.amber,
                        modifier = Modifier
                            .glassSurface(RoundedCornerShape(24.dp))
                            .clickable { loadKey += 1 }
                            .padding(horizontal = 24.dp, vertical = 10.dp),
                    )
                }
                plans == null -> CircularProgressIndicator(color = SleepColors.amber)
                else -> {
                    plans!!.sortedByDescending { it.isAnnual }.forEach { plan ->
                        PlanCard(
                            plan = plan,
                            selected = selected?.id == plan.id,
                            onSelect = { selected = plan },
                        )
                    }
                    message?.let {
                        Spacer(Modifier.height(8.dp))
                        Text(
                            it,
                            style = SleepType.body,
                            color = if (messageIsNotice) SleepColors.amber else SleepColors.danger,
                            textAlign = TextAlign.Center,
                        )
                    }
                    Spacer(Modifier.height(16.dp))
                    PrimaryButton(
                        text = when {
                            busy -> "One moment…"
                            trialDays > 0 -> "Start $trialDays nights free"
                            else -> "Unlock SleepBlock"
                        },
                        enabled = !busy && selected != null,
                    ) {
                        val plan = selected ?: return@PrimaryButton
                        val activity = context as? Activity ?: return@PrimaryButton
                        message = null
                        busy = true
                        scope.launch {
                            try {
                                store.purchase(activity, plan)
                                // Entitled: the root gate swaps to Main on its own.
                            } catch (e: Exception) {
                                message = e.message ?: "Purchase failed. Try again."
                                messageIsNotice = false
                            } finally {
                                busy = false
                            }
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        selected?.let { plan ->
                            if (plan.isAnnual) "${plan.price}/year after the trial · cancel anytime"
                            else "${plan.price}/month · cancel anytime"
                        } ?: "",
                        style = SleepType.body,
                        fontSize = 13.sp,
                        color = SleepColors.muted,
                    )
                }
            }
            Spacer(Modifier.height(20.dp))
            Text(
                "Restore purchases",
                style = SleepType.body,
                fontSize = 14.sp,
                color = SleepColors.dim,
                modifier = Modifier
                    .clickable(enabled = !busy) {
                        message = null
                        scope.launch {
                            try {
                                val entitled = store.restorePurchases()
                                if (!entitled) {
                                    message = "No subscription to restore on this Google account."
                                    messageIsNotice = true
                                }
                            } catch (e: Exception) {
                                message = e.message ?: "Restore failed. Try again."
                                messageIsNotice = false
                            }
                        }
                    }
                    .padding(8.dp),
            )
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun PlanCard(plan: SleepPlan, selected: Boolean, onSelect: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 12.dp)
            .alpha(if (selected) 1f else 0.55f)
            .glassSurface(shape)
            .then(if (selected) Modifier.border(2.dp, SleepColors.amber, shape) else Modifier)
            .clickable(onClick = onSelect)
            .padding(20.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    if (plan.isAnnual && plan.trialDays > 0) "Start for free" else plan.title,
                    style = SleepType.body,
                    fontWeight = FontWeight.Medium,
                )
                if (plan.isAnnual) {
                    Text(
                        "billed annually at ${plan.price}",
                        style = SleepType.body,
                        fontSize = 13.sp,
                        color = SleepColors.muted,
                    )
                }
            }
            Text(
                plan.monthlyEquivalent?.let { "$it/mo" } ?: "${plan.price}/mo",
                style = SleepType.body,
                color = SleepColors.gold,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}
