package com.sulav.sleepblock.widget

import android.content.Context
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.sulav.sleepblock.MainActivity
import com.sulav.sleepblock.R
import com.sulav.sleepblock.data.SleepFormatting
import com.sulav.sleepblock.data.SleepPersistence

/**
 * The small "tonight" widget (mirrors the iOS small widget's job): a bedtime
 * instrument, not a stats tile. Awake it shows the BEDTIME kicker, the hero
 * clock time, and the sloth; asleep it wears the sleep face — the ember
 * night sloth and ASLEEP over the since-time. Honest data only: with no
 * profile it invites setup. A tap opens the app; nothing starts a session
 * from the home screen (the slide gesture stays the only way in).
 */
class SleepWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val persistence = SleepPersistence(context)
        val profile = persistence.profile
        val asleepSince = persistence.activeSession?.start
        provideContent {
            GlanceTheme {
                Column(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = GlanceModifier
                        .fillMaxSize()
                        .background(ImageProvider(R.drawable.widget_night_bg))
                        .clickable(actionStartActivity<MainActivity>())
                        .padding(12.dp),
                ) {
                    when {
                        asleepSince != null -> {
                            Image(
                                provider = ImageProvider(R.drawable.sloth_night),
                                contentDescription = null,
                                modifier = GlanceModifier.width(72.dp).height(43.dp),
                            )
                            Spacer(GlanceModifier.height(6.dp))
                            Text("ASLEEP", style = kickerStyle)
                            Text(
                                "since ${
                                    SleepFormatting.clockTime(
                                        asleepSince.atZone(java.time.ZoneId.systemDefault())
                                            .toLocalTime()
                                            .let { it.hour * 60 + it.minute }
                                    )
                                }",
                                style = TextStyle(color = ColorProvider(EmberDim), fontSize = 13.sp),
                            )
                        }
                        profile != null -> {
                            Text("BEDTIME", style = kickerStyle)
                            Spacer(GlanceModifier.height(2.dp))
                            Text(
                                SleepFormatting.clockTime(profile.bedtime),
                                style = TextStyle(
                                    color = ColorProvider(Gold),
                                    fontSize = 24.sp,
                                    fontWeight = FontWeight.Medium,
                                ),
                            )
                            Spacer(GlanceModifier.height(6.dp))
                            Row {
                                Image(
                                    provider = ImageProvider(R.drawable.sloth_home_awake),
                                    contentDescription = null,
                                    modifier = GlanceModifier.width(84.dp).height(50.dp),
                                )
                            }
                        }
                        else -> {
                            Text("Set a schedule", style = TextStyle(color = ColorProvider(Dim), fontSize = 14.sp))
                        }
                    }
                }
            }
        }
    }

    private val kickerStyle = TextStyle(
        color = ColorProvider(Muted),
        fontSize = 11.sp,
        fontWeight = FontWeight.Medium,
    )

    companion object {
        // Glance runs outside the app theme; palette constants mirror SleepColors.
        private val Gold = Color(0xFFE9C46A)
        private val Dim = Color(0xFFB7BDC7)
        private val Muted = Color(0xFF7A8795)
        private val EmberDim = Color(0xFF9C5A36)

        /** Refresh every placed widget; called after each persistence write. */
        suspend fun refresh(context: Context) {
            runCatching { SleepWidget().updateAll(context) }
        }
    }
}

class SleepWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = SleepWidget()
}
