package com.sulav.sleepblock.blocking

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sulav.sleepblock.R
import com.sulav.sleepblock.data.SleepFormatting
import com.sulav.sleepblock.data.SleepPersistence
import com.sulav.sleepblock.ui.theme.PrimaryButton
import com.sulav.sleepblock.ui.theme.SleepBlockTheme
import com.sulav.sleepblock.ui.theme.SleepColors
import com.sulav.sleepblock.ui.theme.SleepType

/**
 * What a blocked app shows at 2am — the one brand surface the user meets at
 * their weakest moment, so it speaks in the app's own voice (the iOS shield
 * grammar, ShieldConfigProvider.swift): the night sloth, "Time to sleep",
 * and a single honest "Good night" button that goes home. Deliberately no
 * way through to the blocked app.
 */
class ShieldActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            SleepBlockTheme {
                ShieldScreen(
                    wakeMinutes = SleepPersistence(this).profile?.wakeTime,
                    onGoodNight = { goHome() },
                )
            }
        }
    }

    // Back should not return to the blocked app either.
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        goHome()
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        finish()
    }
}

@Composable
private fun ShieldScreen(wakeMinutes: Int?, onGoodNight: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .systemBarsPadding()
            .padding(horizontal = 32.dp),
    ) {
        Spacer(Modifier.weight(1f))
        Image(
            painter = painterResource(R.drawable.sloth_night),
            contentDescription = null,
            modifier = Modifier.fillMaxWidth(0.55f),
        )
        Spacer(Modifier.height(32.dp))
        Text("Time to sleep", style = SleepType.hero, fontSize = 32.sp, color = SleepColors.ink)
        Spacer(Modifier.height(12.dp))
        Text(
            buildString {
                append("This app is asleep until you wake")
                wakeMinutes?.let { append(" at ${SleepFormatting.clockTime(it)}") }
                append(". Head back to bed.")
            },
            style = SleepType.body,
            color = SleepColors.dim,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.weight(1f))
        PrimaryButton("Good night", onClick = onGoodNight)
        Spacer(Modifier.height(48.dp))
    }
}
