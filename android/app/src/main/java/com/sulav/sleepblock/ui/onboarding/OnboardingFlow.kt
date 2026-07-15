package com.sulav.sleepblock.ui.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sulav.sleepblock.R
import com.sulav.sleepblock.auth.SulavAuth
import com.sulav.sleepblock.data.LateNightPhoneTime
import com.sulav.sleepblock.data.OnboardingAnswers
import com.sulav.sleepblock.data.SleepFormatting
import com.sulav.sleepblock.data.SleepGoal
import com.sulav.sleepblock.data.SleepMath
import com.sulav.sleepblock.data.SleepStore
import com.sulav.sleepblock.data.SleepStruggle
import com.sulav.sleepblock.data.TimeSinkApp
import com.sulav.sleepblock.data.WakeFeeling
import com.sulav.sleepblock.ui.theme.NightBackground
import com.sulav.sleepblock.ui.theme.PrimaryButton
import com.sulav.sleepblock.ui.theme.SectionLabel
import com.sulav.sleepblock.ui.theme.SleepColors
import com.sulav.sleepblock.ui.theme.SleepType
import com.sulav.sleepblock.ui.theme.WheelTimePicker
import com.sulav.sleepblock.ui.theme.glassSurface
import kotlinx.coroutines.delay

/**
 * The pre-app gate, mirroring ios OnboardingView: a welcome screen with two
 * independent paths — sign-up (questionnaire first, account as its final
 * step) and a standalone sign-in. A signed-in user with no profile (fresh
 * device, no cloud copy) gets the same questions as a quick setup with no
 * account step.
 */
@Composable
fun OnboardingFlow(store: SleepStore) {
    var route by rememberSaveable { mutableStateOf(if (store.isAuthenticated) Route.QUESTIONS else Route.WELCOME) }

    // A sign-in that restored a cloud profile finishes the flow from under us;
    // RootScreen swaps to Main on its own. Nothing to do here.
    NightBackground {
        AnimatedContent(
            targetState = route,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "onboarding",
        ) { current ->
            when (current) {
                Route.WELCOME -> WelcomeScreen(
                    onGetStarted = { route = Route.QUESTIONS },
                    onSignIn = { route = Route.SIGN_IN },
                )
                Route.SIGN_IN -> SignInScreen(store, onBack = {
                    store.clearAuthMessage()
                    route = Route.WELCOME
                })
                Route.QUESTIONS -> QuestionnaireScreen(store, onExit = {
                    store.clearAuthMessage()
                    route = Route.WELCOME
                })
            }
        }
    }
}

private enum class Route { WELCOME, SIGN_IN, QUESTIONS }

// MARK: - Welcome

@Composable
private fun WelcomeScreen(onGetStarted: () -> Unit, onSignIn: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        // The brand mark: the icon's sleeping sloth (generated art, see
        // scripts/generate-android-assets.py). Decorative only.
        Image(
            painter = painterResource(R.drawable.sloth_brand),
            contentDescription = null,
            modifier = Modifier.fillMaxWidth(0.5f),
        )
        Spacer(Modifier.height(24.dp))
        Text("SleepBlock", style = SleepType.hero)
        Spacer(Modifier.height(12.dp))
        Text("Block apps and log your sleep", style = SleepType.body, color = SleepColors.dim)
        Spacer(Modifier.weight(1f))
        PrimaryButton("Get started", onClick = onGetStarted)
        Spacer(Modifier.height(16.dp))
        Text(
            "I already have an account",
            style = SleepType.body,
            color = SleepColors.dim,
            modifier = Modifier
                .clickable(onClick = onSignIn)
                .padding(12.dp),
        )
        Spacer(Modifier.height(24.dp))
    }
}

// MARK: - Sign in

/**
 * The returning-user path, in the iOS "Welcome back" grammar: the brand
 * sloth centered as a hero over the title, the provider stack anchored at
 * the bottom (Google's white pill, then the quiet glass email path). The
 * email form replaces the stack in place; back unwinds form → providers →
 * welcome, mirroring the iOS edge-swipe rule.
 */
@Composable
private fun SignInScreen(store: SleepStore, onBack: () -> Unit) {
    var showEmailForm by rememberSaveable { mutableStateOf(false) }
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }

    val back: () -> Unit = {
        if (showEmailForm) {
            store.clearAuthMessage()
            showEmailForm = false
        } else {
            onBack()
        }
    }
    BackHandler(onBack = back)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .systemBarsPadding()
            .padding(horizontal = 24.dp),
    ) {
        BackChevron(back)
        Spacer(Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
            Image(
                painter = painterResource(R.drawable.sloth_brand),
                contentDescription = null,
                modifier = Modifier.fillMaxWidth(0.45f),
            )
            Spacer(Modifier.height(24.dp))
            Text("Welcome back", style = SleepType.hero, fontSize = 34.sp)
            Spacer(Modifier.height(8.dp))
            Text("Sign in to pick up your sleep record.", style = SleepType.body, color = SleepColors.dim)
        }
        Spacer(Modifier.weight(1f))

        if (showEmailForm) {
            AuthFields(
                email = email, onEmail = { email = it },
                password = password, onPassword = { password = it },
            )
            AuthMessage(store)
            Spacer(Modifier.height(16.dp))
            PrimaryButton(
                if (store.isAuthenticating) "Signing in…" else "Sign in",
                enabled = !store.isAuthenticating && email.isNotBlank() && password.isNotBlank(),
            ) {
                store.signInEmail(email.trim(), password)
            }
        } else {
            AuthMessage(store)
            Spacer(Modifier.height(16.dp))
            GoogleProviderButton(store, label = "Sign in with Google")
            Spacer(Modifier.height(12.dp))
            EmailProviderButton(label = "Sign in with email") { showEmailForm = true }
        }
        Spacer(Modifier.height(24.dp))
    }
}

/**
 * The branded provider pill: white, the official multicolor "G", one shared
 * label size — deliberately never the app's amber (that gradient is for the
 * app's own actions). Always rendered; an unconfigured build answers the
 * tap with a calm error instead of hiding the path.
 */
@Composable
private fun GoogleProviderButton(store: SleepStore, label: String) {
    val activity = LocalContext.current as? android.app.Activity ?: return
    Row(
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .height(58.dp)
            .background(Color.White, CircleShape)
            .clickable(enabled = !store.isAuthenticating) { store.signInWithGoogle(activity) },
    ) {
        Image(
            painter = painterResource(R.drawable.ic_google_g),
            contentDescription = null,
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.width(10.dp))
        Text(label, fontSize = 17.sp, color = Color(0xFF1F1F1F), fontWeight = FontWeight.Medium)
    }
}

/** The quiet glass email path with an ink envelope. */
@Composable
private fun EmailProviderButton(label: String, onClick: () -> Unit) {
    Row(
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .height(58.dp)
            .glassSurface(RoundedCornerShape(29.dp))
            .clickable(onClick = onClick),
    ) {
        Icon(Icons.Default.MailOutline, null, tint = SleepColors.ink, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(10.dp))
        Text(label, fontSize = 17.sp, color = SleepColors.ink, fontWeight = FontWeight.Medium)
    }
}

// MARK: - Questionnaire

private enum class Step {
    NAME, GOAL, STRUGGLES, TIME_SINKS, PHONE_TIME, WAKE_FEELING, BEDTIME, WAKE, PLAN, ACCOUNT;

    companion object {
        /** Signed-in quick setup skips the account step. */
        fun steps(needsAccount: Boolean): List<Step> =
            if (needsAccount) entries else entries.dropLast(1)
    }
}

@Composable
private fun QuestionnaireScreen(store: SleepStore, onExit: () -> Unit) {
    // Decided once when the flow opens: the moment the account step's sign-up
    // succeeds, isAuthenticated flips mid-composition — recomputing this would
    // shrink the steps list under a live index and crash before the
    // completeOnboarding effect can run.
    val needsAccount = remember { !store.isAuthenticated }
    val steps = remember { Step.steps(needsAccount) }
    var index by rememberSaveable { mutableStateOf(0) }
    val step = steps[index.coerceIn(0, steps.lastIndex)]

    // Answers
    var name by rememberSaveable { mutableStateOf("") }
    var goal by rememberSaveable { mutableStateOf("") }
    var struggles by rememberSaveable { mutableStateOf(setOf<String>()) }
    var timeSinks by rememberSaveable { mutableStateOf(setOf<String>()) }
    var phoneTime by rememberSaveable { mutableStateOf("") }
    var wakeFeeling by rememberSaveable { mutableStateOf("") }
    var bedtime by rememberSaveable { mutableStateOf(23 * 60) }       // 11:00 PM
    var wakeTime by rememberSaveable { mutableStateOf(7 * 60) }       // 7:00 AM
    // The schedule wheels must actually be touched before Next enables —
    // every step requires an interaction (see DESIGN.md, Android note).
    var bedtimeTouched by rememberSaveable { mutableStateOf(false) }
    var wakeTouched by rememberSaveable { mutableStateOf(false) }
    var planRevealed by rememberSaveable { mutableStateOf(false) }

    val answers = OnboardingAnswers(
        name = name,
        bedtime = bedtime,
        wakeTime = wakeTime,
        struggles = struggles.toList(),
        timeSinks = timeSinks.toList(),
        goal = goal,
        lateNightPhone = phoneTime,
        wakeFeeling = wakeFeeling,
    )

    val back: () -> Unit = {
        store.clearAuthMessage()
        if (index == 0) onExit() else index -= 1
    }
    BackHandler(onBack = back)

    // Account step: once auth succeeds, commit the questionnaire — unless the
    // sign-in matched an existing account whose cloud profile was restored
    // (then the fresh answers would overwrite the older account's plan).
    LaunchedEffect(store.isAuthenticated) {
        if (store.isAuthenticated && step == Step.ACCOUNT) {
            if (store.lastSignInWasNewAccount || store.profile == null) {
                store.completeOnboarding(answers)
            }
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 24.dp),
    ) {
        // Progress header: chevron + centered bar.
        Row(verticalAlignment = Alignment.CenterVertically) {
            BackChevron(back)
            LinearProgressIndicator(
                progress = { (index + 1f) / steps.size },
                color = SleepColors.amber,
                trackColor = SleepColors.hairline,
                modifier = Modifier.weight(1f).padding(horizontal = 16.dp),
            )
            Spacer(Modifier.size(48.dp))
        }
        Spacer(Modifier.height(32.dp))

        AnimatedContent(
            targetState = step,
            transitionSpec = {
                val forward = steps.indexOf(targetState) >= steps.indexOf(initialState)
                val dir = if (forward) 1 else -1
                (slideInHorizontally { it * dir / 3 } + fadeIn()) togetherWith
                    (slideOutHorizontally { -it * dir / 3 } + fadeOut())
            },
            label = "step",
            modifier = Modifier.weight(1f),
        ) { current ->
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                when (current) {
                    Step.NAME -> QuestionPage("What's your first name?", null) {
                        OutlinedTextField(
                            value = name,
                            onValueChange = { name = it },
                            placeholder = { Text("Your name", color = SleepColors.muted) },
                            singleLine = true,
                            colors = fieldColors(),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    Step.GOAL -> QuestionPage("What do you want most?", "One goal the plan speaks to.") {
                        SleepGoal.entries.forEach { option ->
                            OptionRow(option.title, selected = goal == option.raw) { goal = option.raw }
                        }
                    }
                    Step.STRUGGLES -> QuestionPage("What gets in the way of your sleep?", "Choose any that apply.") {
                        SleepStruggle.entries.forEach { option ->
                            OptionRow(option.title, selected = option.raw in struggles) {
                                struggles = struggles.toggle(option.raw)
                            }
                        }
                    }
                    Step.TIME_SINKS -> QuestionPage("Which apps keep you up?", "Choose any that apply.") {
                        TimeSinkApp.entries.forEach { option ->
                            OptionRow(option.title, selected = option.raw in timeSinks) {
                                timeSinks = timeSinks.toggle(option.raw)
                            }
                        }
                    }
                    Step.PHONE_TIME -> QuestionPage(
                        "Once you're in bed, how long does the phone keep you up?", null
                    ) {
                        LateNightPhoneTime.entries.forEach { option ->
                            OptionRow(option.title, selected = phoneTime == option.raw) { phoneTime = option.raw }
                        }
                    }
                    Step.WAKE_FEELING -> QuestionPage("How do you usually wake up?", null) {
                        WakeFeeling.entries.forEach { option ->
                            OptionRow(option.title, selected = wakeFeeling == option.raw) { wakeFeeling = option.raw }
                        }
                    }
                    Step.BEDTIME -> QuestionPage("When do you want to go to bed?", "The schedule SleepBlock holds you to.") {
                        WheelTimePicker(
                            minutes = bedtime,
                            onChange = { bedtime = it },
                            onInteracted = { bedtimeTouched = true },
                        )
                    }
                    Step.WAKE -> QuestionPage("And when do you want to wake up?", sleepWindowLine(bedtime, wakeTime)) {
                        WheelTimePicker(
                            minutes = wakeTime,
                            onChange = { wakeTime = it },
                            onInteracted = { wakeTouched = true },
                        )
                    }
                    Step.PLAN -> PlanReveal(
                        answers = answers,
                        revealed = planRevealed,
                        onRevealed = { planRevealed = true },
                    )
                    Step.ACCOUNT -> AccountStep(store)
                }
            }
        }

        // Pinned bottom action. Every step requires a real interaction
        // before Next enables — nobody can tap through blank.
        val nextEnabled = when (step) {
            Step.NAME -> name.isNotBlank()
            Step.GOAL -> goal.isNotEmpty()
            Step.STRUGGLES -> struggles.isNotEmpty()
            Step.TIME_SINKS -> timeSinks.isNotEmpty()
            Step.PHONE_TIME -> phoneTime.isNotEmpty()
            Step.WAKE_FEELING -> wakeFeeling.isNotEmpty()
            Step.BEDTIME -> bedtimeTouched
            Step.WAKE -> wakeTouched
            Step.PLAN -> planRevealed
            Step.ACCOUNT -> true
        }
        if (step != Step.ACCOUNT) {
            PrimaryButton(
                text = when (step) {
                    Step.PLAN -> "I'm ready"
                    else -> "Next"
                },
                enabled = nextEnabled,
            ) {
                if (index == steps.lastIndex) {
                    // Signed-in quick setup ends at the plan reveal.
                    store.completeOnboarding(answers)
                } else {
                    index += 1
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun QuestionPage(title: String, supporting: String?, content: @Composable () -> Unit) {
    Text(title, style = SleepType.title, fontSize = 28.sp, fontWeight = FontWeight.Medium)
    supporting?.let {
        Spacer(Modifier.height(8.dp))
        Text(it, style = SleepType.body, color = SleepColors.dim)
    }
    Spacer(Modifier.height(32.dp))
    content()
}

/** Full-width capsule row with a trailing circle that fills amber when chosen. */
@Composable
private fun OptionRow(title: String, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(28.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 12.dp)
            .glassSurface(shape)
            // The selection ring is one of the strokes that carries meaning.
            .then(if (selected) Modifier.border(2.dp, SleepColors.amber, shape) else Modifier)
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 16.dp),
    ) {
        Text(title, style = SleepType.body, modifier = Modifier.weight(1f))
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(24.dp)
                .background(if (selected) SleepColors.amber else SleepColors.glass, CircleShape)
                .border(1.dp, SleepColors.border, CircleShape),
        ) {
            if (selected) Icon(Icons.Default.Check, null, tint = SleepColors.navy, modifier = Modifier.size(16.dp))
        }
    }
}

private fun Set<String>.toggle(value: String): Set<String> =
    if (value in this) this - value else this + value

private fun sleepWindowLine(bedtime: Int, wakeTime: Int): String {
    val window = SleepMath.windowMinutes(bedtime, wakeTime)
    return "That's ${SleepFormatting.duration(window)} of sleep a night."
}

// MARK: - Plan reveal

@Composable
private fun PlanReveal(answers: OnboardingAnswers, revealed: Boolean, onRevealed: () -> Unit) {
    // The build beat is sticky: backing in from the account step shows the
    // summary instantly (revealed survives via rememberSaveable upstream).
    LaunchedEffect(Unit) {
        if (!revealed) {
            delay(1_800)
            onRevealed()
        }
    }
    if (!revealed) {
        // The build beat: the brand sloth and status line centered together,
        // its presence the only motion — deliberately never a bare spinner.
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.fillMaxWidth().padding(top = 64.dp),
        ) {
            Image(
                painter = painterResource(R.drawable.sloth_brand),
                contentDescription = null,
                modifier = Modifier.fillMaxWidth(0.4f),
            )
            Spacer(Modifier.height(24.dp))
            CircularProgressIndicator(color = SleepColors.amber, modifier = Modifier.size(22.dp))
            Spacer(Modifier.height(16.dp))
            Text("Building your sleep plan…", style = SleepType.body, color = SleepColors.dim)
        }
        return
    }

    val window = SleepMath.windowMinutes(answers.bedtime, answers.wakeTime)
    val phone = LateNightPhoneTime.entries.find { it.raw == answers.lateNightPhone }
    val goal = SleepGoal.entries.find { it.raw == answers.goal }
    val sinkNames = answers.timeSinks
        .mapNotNull { raw -> TimeSinkApp.entries.find { it.raw == raw }?.title }

    QuestionPage("Your sleep plan is ready", "Built from everything you just told us.") {
        // The hero fact: tonight's window, moon → sun, on one glass card.
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxWidth()
                .glassSurface()
                .border(1.dp, SleepColors.amber.copy(alpha = 0.35f), RoundedCornerShape(20.dp))
                .padding(vertical = 24.dp, horizontal = 20.dp),
        ) {
            SectionLabel("Sleep window")
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Default.DarkMode, null, tint = SleepColors.amber, modifier = Modifier.size(18.dp))
                Text(
                    SleepFormatting.clockTime(answers.bedtime),
                    style = SleepType.hero, fontSize = 24.sp, color = SleepColors.gold, maxLines = 1,
                )
                Text("→", style = SleepType.body, color = SleepColors.muted)
                Icon(Icons.Default.WbSunny, null, tint = SleepColors.gold, modifier = Modifier.size(18.dp))
                Text(
                    SleepFormatting.clockTime(answers.wakeTime),
                    style = SleepType.hero, fontSize = 24.sp, color = SleepColors.gold, maxLines = 1,
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "${SleepFormatting.duration(window)} of sleep a night",
                style = SleepType.body, color = SleepColors.dim,
            )
        }
        Spacer(Modifier.height(12.dp))
        phone?.let {
            PlanFact(
                icon = Icons.Default.HourglassEmpty,
                kicker = "Time to win back",
                value = "${SleepFormatting.duration(it.weeklyMinutes)} a week",
                detail = if (sinkNames.isEmpty()) "from late-night scrolling"
                else "from ${sinkNames.take(3).joinToString(", ")}",
            )
        }
        goal?.let {
            PlanFact(
                icon = Icons.Default.Flag,
                kicker = "Your goal",
                value = it.title,
                detail = null,
            )
        }
    }
}

@Composable
private fun PlanFact(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    kicker: String,
    value: String,
    detail: String?,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 12.dp)
            .glassSurface()
            .padding(horizontal = 20.dp, vertical = 18.dp),
    ) {
        // Glyph chip in the settings-row grammar: soft amber-tinted square.
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(40.dp)
                .background(SleepColors.amber.copy(alpha = 0.14f), RoundedCornerShape(12.dp)),
        ) {
            Icon(icon, null, tint = SleepColors.amber, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(16.dp))
        Column {
            SectionLabel(kicker)
            Spacer(Modifier.height(4.dp))
            Text(value, style = SleepType.title, fontSize = 20.sp, color = SleepColors.gold)
            detail?.let {
                Spacer(Modifier.height(2.dp))
                Text(it, style = SleepType.body, fontSize = 14.sp, color = SleepColors.dim)
            }
        }
    }
}

// MARK: - Account step

@Composable
private fun AccountStep(store: SleepStore) {
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }

    QuestionPage("Save your sleep plan", "Create an account so your plan and record follow you.") {
        GoogleProviderButton(store, label = "Sign up with Google")
        Spacer(Modifier.height(20.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            HorizontalDivider(color = SleepColors.hairline, modifier = Modifier.weight(1f))
            Text(
                "or with email",
                style = SleepType.label,
                modifier = Modifier.padding(horizontal = 12.dp),
            )
            HorizontalDivider(color = SleepColors.hairline, modifier = Modifier.weight(1f))
        }
        Spacer(Modifier.height(20.dp))
        AuthFields(
            email = email, onEmail = { email = it },
            password = password, onPassword = { password = it },
        )
        AuthMessage(store)
        Spacer(Modifier.height(24.dp))
        PrimaryButton(
            if (store.isAuthenticating) "Creating account…" else "Sign up with email",
            enabled = !store.isAuthenticating && email.isNotBlank() && password.length >= 6,
        ) {
            store.signUpEmail(email.trim(), password)
        }
        Spacer(Modifier.height(24.dp))
    }
}

// MARK: - Shared auth pieces

@Composable
private fun AuthFields(
    email: String, onEmail: (String) -> Unit,
    password: String, onPassword: (String) -> Unit,
) {
    OutlinedTextField(
        value = email,
        onValueChange = onEmail,
        placeholder = { Text("Email", color = SleepColors.muted) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
        colors = fieldColors(),
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(12.dp))
    OutlinedTextField(
        value = password,
        onValueChange = onPassword,
        placeholder = { Text("Password", color = SleepColors.muted) },
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        colors = fieldColors(),
        modifier = Modifier.fillMaxWidth(),
    )
}

/** Two-tone rule: failures in danger red, normal next steps in calm amber. */
@Composable
private fun AuthMessage(store: SleepStore) {
    store.authErrorMessage?.let { message ->
        Spacer(Modifier.height(16.dp))
        Text(
            message,
            style = SleepType.body,
            color = if (store.authMessageIsNotice) SleepColors.amber else SleepColors.danger,
        )
    }
}

@Composable
private fun fieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = SleepColors.amber,
    unfocusedBorderColor = SleepColors.border,
    focusedTextColor = SleepColors.ink,
    unfocusedTextColor = SleepColors.ink,
    cursorColor = SleepColors.amber,
    focusedContainerColor = SleepColors.glass,
    unfocusedContainerColor = SleepColors.glass,
)

@Composable
private fun BackChevron(onClick: () -> Unit) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(48.dp).glassSurface(RoundedCornerShape(24.dp)),
    ) {
        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = SleepColors.ink)
    }
}
