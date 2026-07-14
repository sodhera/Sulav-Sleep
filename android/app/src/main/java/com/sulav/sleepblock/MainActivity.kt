package com.sulav.sleepblock

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sulav.sleepblock.data.SleepStore
import com.sulav.sleepblock.ui.MainScreen
import com.sulav.sleepblock.ui.onboarding.OnboardingFlow
import com.sulav.sleepblock.ui.paywall.PaywallScreen
import com.sulav.sleepblock.ui.sleep.SleepModeScreen
import com.sulav.sleepblock.ui.theme.NightBackground
import com.sulav.sleepblock.ui.theme.SleepBlockTheme
import com.sulav.sleepblock.ui.theme.SleepColors

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            SleepBlockTheme {
                RootScreen()
            }
        }
    }
}

/**
 * Route mirror of ios RootView: splash until auth restore resolves, the sleep
 * screen always outranks everything while a night runs, then onboarding/auth
 * until signed in + onboarded, then Main.
 */
@Composable
fun RootScreen(store: SleepStore = viewModel()) {
    val destination = when {
        !store.isAuthReady -> Destination.SPLASH
        // An active night always outranks the paywall: Hold to wake (and the
        // lockdown teardown) stays reachable whatever the entitlement says.
        store.activeSession != null -> Destination.SLEEP
        !store.isAuthenticated || !store.isOnboarded -> Destination.ONBOARDING
        store.needsPaywall -> Destination.PAYWALL
        else -> Destination.MAIN
    }
    Crossfade(targetState = destination, label = "root") { target ->
        when (target) {
            Destination.SPLASH -> NightBackground {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = SleepColors.amber)
                }
            }
            Destination.SLEEP -> SleepModeScreen(store)
            Destination.ONBOARDING -> OnboardingFlow(store)
            Destination.PAYWALL -> PaywallScreen(store)
            Destination.MAIN -> MainScreen(store)
        }
    }
}

private enum class Destination { SPLASH, SLEEP, ONBOARDING, PAYWALL, MAIN }
