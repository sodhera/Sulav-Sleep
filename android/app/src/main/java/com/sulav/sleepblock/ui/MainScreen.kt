package com.sulav.sleepblock.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.sulav.sleepblock.data.AppTab
import com.sulav.sleepblock.data.SleepStore
import com.sulav.sleepblock.ui.home.HomeScreen
import com.sulav.sleepblock.ui.profile.ProfileScreen
import com.sulav.sleepblock.ui.theme.NightBackground
import com.sulav.sleepblock.ui.theme.SleepColors
import com.sulav.sleepblock.ui.theme.glassSurface

/** Two tabs, each with exactly one job: Home — go to bed; Profile — you. */
@Composable
fun MainScreen(store: SleepStore) {
    NightBackground {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f)) {
                AnimatedContent(
                    targetState = store.selectedTab,
                    transitionSpec = { fadeIn() togetherWith fadeOut() },
                    label = "tab",
                ) { tab ->
                    when (tab) {
                        AppTab.HOME -> HomeScreen(store)
                        AppTab.PROFILE -> ProfileScreen(store)
                    }
                }
            }
            // The confirmation panel owns the whole screen; hide the nav there.
            if (!store.showSleepConfirmation) {
                Row(
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp),
                    modifier = Modifier
                        .navigationBarsPadding()
                        .padding(bottom = 12.dp)
                        .glassSurface(androidx.compose.foundation.shape.RoundedCornerShape(28.dp))
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .align(Alignment.CenterHorizontally),
                ) {
                    TabIcon(store, AppTab.HOME)
                    TabIcon(store, AppTab.PROFILE)
                }
            }
        }
    }
}

@Composable
private fun TabIcon(store: SleepStore, tab: AppTab) {
    val selected = store.selectedTab == tab
    val haptics = com.sulav.sleepblock.ui.theme.rememberHaptics()
    IconButton(onClick = {
        haptics.knock()
        store.selectedTab = tab
    }) {
        Icon(
            imageVector = if (tab == AppTab.HOME) Icons.Default.Home else Icons.Default.Person,
            contentDescription = if (tab == AppTab.HOME) "Home" else "Profile",
            tint = if (selected) SleepColors.amber else SleepColors.muted,
        )
    }
}
