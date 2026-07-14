package com.sulav.sleepblock.ui.profile

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.graphics.drawable.toBitmap
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.sulav.sleepblock.blocking.SleepAppBlocking
import com.sulav.sleepblock.data.SleepStore
import com.sulav.sleepblock.ui.theme.NightBackground
import com.sulav.sleepblock.ui.theme.SectionLabel
import com.sulav.sleepblock.ui.theme.SleepColors
import com.sulav.sleepblock.ui.theme.SleepType
import com.sulav.sleepblock.ui.theme.glassSurface

/**
 * The Blocked apps page (iOS grammar, Android permissions): the "Block
 * while you sleep" toggle, the two special-permission rows that deep-link
 * into system Settings, and the launcher-app checklist. Choosing apps is
 * the commitment — a fresh selection blocks tonight with no extra step.
 */
@Composable
fun BlockedAppsSheet(store: SleepStore, onClose: () -> Unit) {
    val context = LocalContext.current
    // Re-check the special permissions every time we return from Settings.
    var permissionRevision by remember { mutableStateOf(0) }
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(lifecycleOwner) {
        // Dialogs don't get their own resume events; observe the host's.
        lifecycleOwner.lifecycle.addObserver(
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) permissionRevision += 1
            }
        )
    }
    val hasUsage = remember(permissionRevision) { SleepAppBlocking.hasUsageAccess(context) }
    val hasOverlay = remember(permissionRevision) { SleepAppBlocking.hasOverlayPermission(context) }
    val apps = remember { SleepAppBlocking.installedApps(context) }
    val selected = store.blockedPackages

    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        NightBackground {
            Column(Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 24.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(
                        onClick = onClose,
                        modifier = Modifier.size(48.dp).glassSurface(RoundedCornerShape(24.dp)),
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = SleepColors.ink)
                    }
                    Spacer(Modifier.size(16.dp))
                    Text("Blocked apps", style = SleepType.hero, fontSize = 30.sp)
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    "Locked from Sleep Now until you wake. Calls always work.",
                    style = SleepType.body,
                    color = SleepColors.dim,
                )
                Spacer(Modifier.height(24.dp))

                LazyColumn(Modifier.fillMaxSize()) {
                    item {
                        Column(Modifier.fillMaxWidth().glassSurface().padding(horizontal = 20.dp)) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                            ) {
                                Text("Block while you sleep", style = SleepType.body, modifier = Modifier.weight(1f))
                                Switch(
                                    checked = store.blockingEnabled,
                                    onCheckedChange = { store.setBlockingEnabled(it) },
                                    colors = SwitchDefaults.colors(
                                        checkedTrackColor = SleepColors.amber,
                                        checkedThumbColor = SleepColors.navy,
                                    ),
                                )
                            }
                        }
                        Spacer(Modifier.height(24.dp))

                        // The two teeth. Both rows disappear once granted.
                        if (!hasUsage || !hasOverlay) {
                            SectionLabel("Permissions")
                            Spacer(Modifier.height(8.dp))
                            Column(Modifier.fillMaxWidth().glassSurface().padding(horizontal = 20.dp)) {
                                if (!hasUsage) {
                                    PermissionRow("Usage access", "Lets SleepBlock see which app opens") {
                                        context.startActivity(SleepAppBlocking.usageAccessSettingsIntent())
                                    }
                                }
                                if (!hasUsage && !hasOverlay) HorizontalDivider(color = SleepColors.hairline)
                                if (!hasOverlay) {
                                    PermissionRow("Display over other apps", "Lets the shield appear at night") {
                                        context.startActivity(SleepAppBlocking.overlaySettingsIntent(context))
                                    }
                                }
                            }
                            Spacer(Modifier.height(24.dp))
                        }

                        SectionLabel("Apps")
                        Spacer(Modifier.height(8.dp))
                    }
                    items(apps, key = { it.packageName }) { app ->
                        val isSelected = app.packageName in selected
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    store.saveBlockedPackages(
                                        if (isSelected) selected - app.packageName
                                        else selected + app.packageName
                                    )
                                }
                                .padding(vertical = 10.dp),
                        ) {
                            Image(
                                bitmap = remember(app.packageName) { app.icon.toBitmap(96, 96).asImageBitmap() },
                                contentDescription = null,
                                modifier = Modifier.size(36.dp),
                            )
                            Spacer(Modifier.size(14.dp))
                            Text(app.label, style = SleepType.body, modifier = Modifier.weight(1f))
                            Box(
                                contentAlignment = Alignment.Center,
                                modifier = Modifier
                                    .size(24.dp)
                                    .background(
                                        if (isSelected) SleepColors.amber else SleepColors.glass,
                                        CircleShape,
                                    ),
                            ) {
                                if (isSelected) {
                                    Icon(
                                        Icons.Default.Check, null,
                                        tint = SleepColors.navy,
                                        modifier = Modifier.size(16.dp),
                                    )
                                }
                            }
                        }
                    }
                    item { Spacer(Modifier.height(48.dp)) }
                }
            }
        }
    }
}

@Composable
private fun PermissionRow(title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 14.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = SleepType.body)
            Text(subtitle, style = SleepType.body, fontSize = 13.sp, color = SleepColors.muted)
        }
        Text("Grant", style = SleepType.body, color = SleepColors.amber)
    }
}
