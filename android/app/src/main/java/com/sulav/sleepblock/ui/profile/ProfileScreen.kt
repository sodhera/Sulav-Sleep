package com.sulav.sleepblock.ui.profile

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.sulav.sleepblock.R
import com.sulav.sleepblock.data.SleepFormatting
import com.sulav.sleepblock.data.SleepSession
import com.sulav.sleepblock.data.SleepStore
import com.sulav.sleepblock.subscription.SubscriptionStatus
import com.sulav.sleepblock.ui.theme.NightBackground
import com.sulav.sleepblock.ui.theme.SectionLabel
import com.sulav.sleepblock.ui.theme.SleepColors
import com.sulav.sleepblock.ui.theme.SleepType
import com.sulav.sleepblock.ui.theme.glassSurface
import kotlinx.coroutines.launch
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale

/**
 * Profile — everything about the user (mirrors ios ProfileView): identity,
 * the stat band, the 7-night bar rhythm, recent nights, and the gear into
 * Settings. Honest data only; no ghost charts or sample numbers.
 */
@Composable
fun ProfileScreen(store: SleepStore) {
    var showSettings by rememberSaveable { mutableStateOf(false) }
    val profile = store.profile ?: return
    val sessions = store.displaySessions

    Column(
        modifier = Modifier
            .fillMaxSize()
            .systemBarsPadding()
            .padding(horizontal = 24.dp)
            .verticalScroll(rememberScrollState()),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(profile.name, style = SleepType.hero, fontSize = 34.sp, modifier = Modifier.weight(1f))
            IconButton(
                onClick = { showSettings = true },
                modifier = Modifier.size(48.dp).glassSurface(RoundedCornerShape(24.dp)),
            ) {
                Icon(Icons.Default.Settings, "Settings", tint = SleepColors.ink)
            }
        }
        Spacer(Modifier.height(24.dp))

        // Stat band: three big numerals over tiny labels.
        Row(Modifier.fillMaxWidth()) {
            Stat("Avg sleep", averageDuration(sessions), Modifier.weight(1f))
            Stat("Streak", if (store.onTrackStreak > 0) "${store.onTrackStreak}" else "—", Modifier.weight(1f))
            Stat("Nights", "${sessions.size}", Modifier.weight(1f))
        }
        Spacer(Modifier.height(32.dp))

        SectionLabel("Sleep record")
        Spacer(Modifier.height(16.dp))
        if (sessions.isEmpty()) {
            // Composed and warm, never a ghost chart.
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.fillMaxWidth().glassSurface().padding(32.dp),
            ) {
                Text("🌙", fontSize = 32.sp)
                Spacer(Modifier.height(8.dp))
                Text("No nights yet", style = SleepType.body, fontWeight = FontWeight.Medium)
                Text("Your record starts tonight.", style = SleepType.body, color = SleepColors.dim)
            }
        } else {
            WeekChart(sessions = sessions, targetMinutes = store.targetMinutes)
            Spacer(Modifier.height(32.dp))
            SectionLabel("Recent nights")
            Spacer(Modifier.height(8.dp))
            sessions.takeLast(10).reversed().forEach { session ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp),
                ) {
                    Text(
                        SleepFormatting.dayLabel(session.end),
                        style = SleepType.body,
                        color = SleepColors.dim,
                        modifier = Modifier.weight(1f),
                    )
                    Text(SleepFormatting.duration(session.durationMinutes), style = SleepType.body)
                }
                HorizontalDivider(color = SleepColors.hairline)
            }
        }
        Spacer(Modifier.height(96.dp))
    }

    if (showSettings) {
        SettingsSheet(store, onClose = { showSettings = false })
    }
}

@Composable
private fun Stat(label: String, value: String, modifier: Modifier = Modifier) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = modifier) {
        Text(value, style = SleepType.title, color = SleepColors.gold)
        Spacer(Modifier.height(2.dp))
        Text(label, style = SleepType.label, fontSize = 10.sp)
    }
}

private fun averageDuration(sessions: List<SleepSession>): String {
    if (sessions.isEmpty()) return "—"
    return SleepFormatting.duration(sessions.sumOf { it.durationMinutes } / sessions.size)
}

/**
 * The widgets' 7-night bar rhythm: exactly 7 fixed-width columns, latest
 * rightmost and full-strength, earlier nights receding, unlogged slots as
 * hairline stubs, a quiet target hairline with ~15% headroom.
 */
@Composable
private fun WeekChart(sessions: List<SleepSession>, targetMinutes: Int) {
    val recent = sessions.takeLast(7)
    val slots: List<SleepSession?> = List(7 - recent.size) { null } + recent
    val maxValue = (maxOf(targetMinutes, recent.maxOfOrNull { it.durationMinutes } ?: 0) * 1.15f)
    val chartHeight = 140.dp

    Box(Modifier.fillMaxWidth().height(chartHeight)) {
        // Target hairline.
        val targetFraction = (targetMinutes / maxValue).coerceIn(0f, 1f)
        Box(
            Modifier
                .fillMaxWidth()
                .padding(top = chartHeight * (1f - targetFraction))
                .height(1.dp)
                .background(SleepColors.hairline),
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Bottom,
            modifier = Modifier.fillMaxSize(),
        ) {
            slots.forEachIndexed { index, session ->
                val isLatest = index == slots.lastIndex && session != null
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.weight(1f),
                ) {
                    if (session != null) {
                        val fraction = (session.durationMinutes / maxValue).coerceIn(0.02f, 1f)
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height((chartHeight - 20.dp) * fraction)
                                .background(
                                    SleepColors.gold.copy(alpha = if (isLatest) 1f else 0.6f),
                                    RoundedCornerShape(6.dp),
                                ),
                        )
                    } else {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height(2.dp)
                                .background(SleepColors.hairline, RoundedCornerShape(1.dp)),
                        )
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        session?.let { weekdayInitial(it) } ?: "·",
                        style = SleepType.label,
                        fontSize = 10.sp,
                        color = if (isLatest) SleepColors.amber else SleepColors.muted,
                    )
                }
            }
        }
    }
}

private fun weekdayInitial(session: SleepSession): String =
    session.end.atZone(ZoneId.systemDefault()).dayOfWeek
        .getDisplayName(TextStyle.NARROW, Locale.US)

// MARK: - Settings

/**
 * Full-screen settings cover: Profile (name/email), Sleep (schedule), and
 * Account (sign out; delete demands the word "delete" typed back — friction
 * proportional to what each exit destroys).
 */
@Composable
private fun SettingsSheet(store: SleepStore, onClose: () -> Unit) {
    val profile = store.profile ?: return
    val context = LocalContext.current
    var showRename by rememberSaveable { mutableStateOf(false) }
    var showSignOut by rememberSaveable { mutableStateOf(false) }
    var showDelete by rememberSaveable { mutableStateOf(false) }
    var showBlockedApps by rememberSaveable { mutableStateOf(false) }
    var bedtime by rememberSaveable(profile.bedtime) { mutableStateOf(profile.bedtime) }
    var wakeTime by rememberSaveable(profile.wakeTime) { mutableStateOf(profile.wakeTime) }
    val scope = rememberCoroutineScope()

    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        NightBackground {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .systemBarsPadding()
                    .padding(horizontal = 24.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Settings", style = SleepType.hero, fontSize = 34.sp, modifier = Modifier.weight(1f))
                    IconButton(
                        onClick = onClose,
                        modifier = Modifier.size(48.dp).glassSurface(RoundedCornerShape(24.dp)),
                    ) {
                        Text("✕", style = SleepType.body, color = SleepColors.ink)
                    }
                }
                Spacer(Modifier.height(32.dp))

                SectionLabel("Profile")
                Spacer(Modifier.height(8.dp))
                SettingsGroup {
                    SettingsRow("Name", profile.name) { showRename = true }
                    HorizontalDivider(color = SleepColors.hairline)
                    SettingsRow("Email", store.account?.email ?: "—", onClick = null)
                }
                Spacer(Modifier.height(32.dp))

                // A locked user gets a different group: the way *in*. Once the
                // first-run paywall is dismissed, Sleep Now is the only other
                // place the plans are reachable, and someone who closed the
                // pitch and then went looking for the price should find it in
                // Settings, where prices live.
                if (store.isLocked) {
                    SectionLabel("Subscription")
                    Spacer(Modifier.height(8.dp))
                    SettingsGroup {
                        // The cover itself lives in MainScreen; its window is
                        // added after this one, so it lands above Settings.
                        SettingsRow("Unlock SleepBlock", "") { store.presentPaywallIfLocked() }
                    }
                    Spacer(Modifier.height(32.dp))
                }

                // What am I on, and when does it change? Hidden when there's
                // no status to show (dev mode, or before the first fetch) —
                // the app never fakes a plan.
                store.subscriptionStatus?.takeIf { !store.isLocked }?.let { status ->
                    SectionLabel("Subscription")
                    Spacer(Modifier.height(8.dp))
                    SettingsGroup {
                        SubscriptionStatusRow(status)
                        HorizontalDivider(color = SleepColors.hairline)
                        SettingsRow("Manage subscription", "") {
                            // The Play-managed sheet is the only sanctioned
                            // place to switch plans or cancel.
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://play.google.com/store/account/subscriptions"),
                                )
                            )
                        }
                    }
                    Spacer(Modifier.height(32.dp))
                }

                SectionLabel("Sleep")
                Spacer(Modifier.height(8.dp))
                SettingsGroup {
                    ScheduleRow("Bedtime", bedtime) {
                        bedtime = it
                        store.saveSchedule(it, wakeTime)
                    }
                    HorizontalDivider(color = SleepColors.hairline)
                    ScheduleRow("Wake up", wakeTime) {
                        wakeTime = it
                        store.saveSchedule(bedtime, it)
                    }
                    HorizontalDivider(color = SleepColors.hairline)
                    SettingsRow(
                        "Blocked apps",
                        when {
                            !store.blockingEnabled -> "Off"
                            store.blockedPackages.isEmpty() -> "None"
                            else -> "${store.blockedPackages.size} chosen"
                        },
                    ) { showBlockedApps = true }
                }
                Spacer(Modifier.height(32.dp))

                SectionLabel("Account")
                Spacer(Modifier.height(8.dp))
                SettingsGroup {
                    SettingsRow("Sign out", "", dim = true) { showSignOut = true }
                }
                Spacer(Modifier.height(24.dp))
                // A rare, irreversible exit that never competes for attention.
                Text(
                    "Delete account",
                    style = SleepType.body,
                    color = SleepColors.muted.copy(alpha = 0.7f),
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .clickable { showDelete = true }
                        .padding(12.dp),
                )
                Spacer(Modifier.height(48.dp))
            }
        }
    }

    if (showBlockedApps) {
        BlockedAppsSheet(store, onClose = { showBlockedApps = false })
    }

    if (showRename) {
        var name by rememberSaveable { mutableStateOf(profile.name) }
        AlertDialog(
            onDismissRequest = { showRename = false },
            containerColor = SleepColors.navy,
            title = { Text("Your name", color = SleepColors.ink) },
            text = {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = SleepColors.amber,
                        unfocusedBorderColor = SleepColors.border,
                        focusedTextColor = SleepColors.ink,
                        unfocusedTextColor = SleepColors.ink,
                        cursorColor = SleepColors.amber,
                    ),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    store.saveName(name)
                    showRename = false
                }) { Text("Save", color = SleepColors.amber) }
            },
            dismissButton = {
                TextButton(onClick = { showRename = false }) { Text("Cancel", color = SleepColors.dim) }
            },
        )
    }

    if (showSignOut) {
        AlertDialog(
            onDismissRequest = { showSignOut = false },
            containerColor = SleepColors.navy,
            title = { Text("Sign out?", color = SleepColors.ink) },
            text = { Text("Your sleep record stays on this device.", color = SleepColors.dim) },
            confirmButton = {
                TextButton(onClick = {
                    showSignOut = false
                    onClose()
                    store.signOut()
                }) { Text("Sign out", color = SleepColors.amber) }
            },
            dismissButton = {
                TextButton(onClick = { showSignOut = false }) { Text("Cancel", color = SleepColors.dim) }
            },
        )
    }

    if (showDelete) {
        var confirmation by rememberSaveable { mutableStateOf("") }
        var deleting by rememberSaveable { mutableStateOf(false) }
        var error by rememberSaveable { mutableStateOf<String?>(null) }
        AlertDialog(
            onDismissRequest = { if (!deleting) showDelete = false },
            containerColor = SleepColors.navy,
            title = { Text("Delete account?", color = SleepColors.ink) },
            text = {
                Column {
                    Text(
                        "This permanently deletes your account and sleep record. Type \"delete\" to confirm.",
                        color = SleepColors.dim,
                    )
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(
                        value = confirmation,
                        onValueChange = { confirmation = it },
                        singleLine = true,
                        enabled = !deleting,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = SleepColors.danger,
                            unfocusedBorderColor = SleepColors.border,
                            focusedTextColor = SleepColors.ink,
                            unfocusedTextColor = SleepColors.ink,
                            cursorColor = SleepColors.danger,
                        ),
                    )
                    error?.let {
                        Spacer(Modifier.height(8.dp))
                        Text(it, color = SleepColors.danger)
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = confirmation.trim().equals("delete", ignoreCase = true) && !deleting,
                    onClick = {
                        deleting = true
                        error = null
                        scope.launch {
                            val failure = store.deleteAccountRemotely()
                            deleting = false
                            if (failure == null) {
                                showDelete = false
                                onClose()
                                store.finalizeAccountDeletion()
                            } else {
                                error = failure
                            }
                        }
                    },
                ) { Text(if (deleting) "Deleting…" else "Delete", color = SleepColors.danger) }
            },
            dismissButton = {
                TextButton(onClick = { showDelete = false }, enabled = !deleting) {
                    Text("Cancel", color = SleepColors.dim)
                }
            },
        )
    }
}

/**
 * The status readout, not a control — the one settings row that earns a dim
 * detail line: the brand sloth as the "you're a subscriber" mark, the tier
 * title, and the renewal fact beneath. "About to end" reads amber — a calm
 * heads-up, never danger.
 */
@Composable
private fun SubscriptionStatusRow(status: SubscriptionStatus) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(40.dp)
                .background(SleepColors.gold.copy(alpha = 0.16f), RoundedCornerShape(12.dp)),
        ) {
            Image(
                painter = painterResource(R.drawable.sloth_brand),
                contentDescription = null,
                modifier = Modifier.size(30.dp),
            )
        }
        Spacer(Modifier.size(14.dp))
        Column {
            Text(
                when (status.tier) {
                    SubscriptionStatus.Tier.TRIAL -> "Free trial"
                    SubscriptionStatus.Tier.PRO -> "SleepBlock Pro"
                    SubscriptionStatus.Tier.NONE -> "Not subscribed"
                },
                style = SleepType.body,
                fontWeight = FontWeight.Medium,
            )
            status.expiresAtMillis?.let { expires ->
                val date = java.time.Instant.ofEpochMilli(expires)
                    .atZone(java.time.ZoneId.systemDefault())
                    .format(java.time.format.DateTimeFormatter.ofPattern("MMM d, yyyy"))
                val (line, color) = when {
                    !status.willRenew -> "Ends $date · won't renew" to SleepColors.amber
                    status.tier == SubscriptionStatus.Tier.TRIAL -> {
                        val days = ((expires - System.currentTimeMillis()) / 86_400_000L).coerceAtLeast(0)
                        "$days days left · renews $date" to SleepColors.muted
                    }
                    else -> "${if (status.isAnnual) "Yearly" else "Monthly"} · Renews $date" to SleepColors.muted
                }
                Text(line, style = SleepType.body, fontSize = 13.sp, color = color)
            }
        }
    }
}

@Composable
private fun SettingsGroup(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().glassSurface().padding(horizontal = 20.dp)) {
        content()
    }
}

@Composable
private fun SettingsRow(title: String, value: String, dim: Boolean = false, onClick: (() -> Unit)?) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(vertical = 18.dp),
    ) {
        Text(title, style = SleepType.body, color = if (dim) SleepColors.dim else SleepColors.ink)
        Spacer(Modifier.weight(1f).padding(start = 16.dp))
        Text(
            value,
            style = SleepType.body,
            color = SleepColors.muted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(start = 16.dp),
        )
    }
}

/** Bedtime/wake row with inline −/＋ 15-minute steppers. */
@Composable
private fun ScheduleRow(title: String, minutes: Int, onChange: (Int) -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
    ) {
        Text(title, style = SleepType.body)
        Spacer(Modifier.weight(1f))
        StepButton("−") { onChange((minutes - 15).mod(1_440)) }
        Text(
            SleepFormatting.clockTime(minutes),
            style = SleepType.body,
            color = SleepColors.amber,
            modifier = Modifier.padding(horizontal = 12.dp),
        )
        StepButton("＋") { onChange((minutes + 15).mod(1_440)) }
    }
}

@Composable
private fun StepButton(symbol: String, onClick: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(36.dp)
            .glassSurface(RoundedCornerShape(18.dp))
            .clickable(onClick = onClick),
    ) {
        Text(symbol, style = SleepType.body, color = SleepColors.ink)
    }
}
