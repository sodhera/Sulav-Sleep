import SwiftUI

// The morning mirror and the reason editor — the two halves of the app's
// answer to "how do we make people not want the hack".
//
// Neither adds a lock. The mirror shows someone what they actually did last
// night, and the editor collects the sentence the shield will use to argue
// back at 1am in their voice instead of ours. See DESIGN.md → Shield overlay.

// MARK: - Morning mirror

/// One quiet line under Home's last-night strip: how many times the user
/// reached for a blocked app, and the window it happened in.
///
/// **A mirror, never a judge.** No red, no "failed", no exclamation. Most
/// people genuinely do not know they reached eleven times between midnight and
/// one, and the plain number moves behaviour further than any wall does — but
/// only while it reads as information. The moment it reads as a scolding it
/// stops being data the user wants to look at, and the app gets deleted.
///
/// Silent on a night with no reaches. A triumphant "0 attempts!" would cheapen
/// the nights that mattered, and there is nothing to reflect.
struct ReachMirrorLine: View {
    let night: ReachNight
    /// Set when the user hasn't written their reasons yet — the line becomes
    /// the invitation. This is the honest moment to ask: the feeling is still
    /// available, which is exactly what sign-up can't offer.
    var invitesReason: Bool = false
    /// False while the lockdown settings are closed: the line still reports
    /// last night, but it stops being a door into the reasons — and the
    /// invitation goes with it, since inviting someone to write a sentence
    /// they can't save is worse than staying quiet.
    var isInteractive: Bool = true
    var action: () -> Void

    var body: some View {
        if isInteractive {
            Button(action: {
                Haptics.heavy()
                action()
            }) {
                line
            }
            .buttonStyle(.plain)
        } else {
            line
        }
    }

    private var line: some View {
        VStack(spacing: SleepSpacing.xs) {
            Text(summary)
                .font(SleepFont.body(13))
                .foregroundStyle(SleepColor.muted)
            if invitesReason && isInteractive {
                Text("Write why you're doing this")
                    .font(SleepFont.label(13))
                    .foregroundStyle(SleepColor.amber)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// "Reached 6 times · 12:40 – 1:10". The span is the insight — the count
    /// alone says how often, the window says *when*, and it's the when that
    /// people recognise themselves in.
    private var summary: String {
        let times = night.count == 1 ? "once" : "\(night.count) times"
        guard let first = night.first, let last = night.last else {
            return "Reached \(times)"
        }
        let span = Calendar.current.dateComponents([.minute], from: first, to: last).minute ?? 0
        // Under a couple of minutes there is no window to speak of, and
        // "12:41 – 12:41" reads like a bug.
        guard span >= 2 else { return "Reached \(times) · \(Self.clock(first))" }
        return "Reached \(times) · \(Self.clock(first)) – \(Self.clock(last))"
    }

    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Reason editor

/// Where the user writes the sentences the shield shows them.
///
/// The whole feature lives or dies on the quality of the sentence, not the
/// plumbing, so the screen is built to produce a true one:
///
/// - **A finished sentence, not a blank box.** The field is prefixed with the
///   stem "I'll know this worked when…" in the placeholder. Blank boxes
///   produce slogans; a stem produces an answer.
/// - **A hard 60-character ceiling**, shown as a live count once they're near
///   it. The shield subtitle is one short line, and the limit doubles as an
///   editing constraint — you cannot fit a slogan and a real reason in sixty
///   characters, so people write the real one.
/// - **Three slots, because the shield rotates.** One line goes invisible in
///   about a week, the same way a desktop wallpaper does.
///
/// The app never writes one of these, and never suggests wording. A sentence
/// that sounds like our copy is worth nothing on the shield — the entire point
/// is that there is no app in it to be annoyed at.
struct ReasonsScreen: View {
    var store: SleepStore

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [String] = ["", "", ""]
    @FocusState private var focused: Int?

    var body: some View {
        SceneScreen {
            SubpageHeader(
                title: "Why you're doing this",
                subtitle: store.lockdownSettingsLocked
                    ? "Tonight's block is quoting these back at you. They can change in the morning."
                    : "Shown on the lock screen when you reach for a blocked app. Your words, not ours."
            )

            if store.lockdownSettingsLocked {
                // These sentences are part of the lock, not a preference about
                // it — the shield's whole argument at 1am is the user's own
                // words, and the self who wants to delete them is exactly the
                // self they were written for.
                LockdownClosedPanel(
                    explanation: "The block is quoting these back at you tonight, so they're closed while it runs. They open again once the night ends."
                )
            } else {
                editor
            }
        }
        .onAppear {
            store.refreshLockdownPhase()
            let existing = store.lockReasons
            drafts = (0..<SleepLockdownSelection.reasonLimit).map {
                $0 < existing.count ? existing[$0] : ""
            }
        }
    }

    /// The three fields and the save button.
    private var editor: some View {
        Group {
            GlassGroup {
                ForEach(0..<SleepLockdownSelection.reasonLimit, id: \.self) { index in
                    if index > 0 { GlassRowDivider() }
                    reasonField(index)
                }
            }
            .padding(.top, SleepSpacing.xl)

            Text("Keep it short and true. The one you'd want to read at 1am.")
                .font(SleepFont.body(13))
                .foregroundStyle(SleepColor.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, SleepSpacing.lg)

            LiquidPrimaryButton(title: "Save", systemImage: "checkmark") {
                store.saveLockReasons(drafts)
                dismiss()
            }
            .padding(.top, SleepSpacing.huge)
        }
    }

    @ViewBuilder
    private func reasonField(_ index: Int) -> some View {
        HStack(spacing: SleepSpacing.md) {
            GlassRowIcon(
                icon: index == 0 ? "quote.opening" : "plus",
                color: index == 0 ? SleepColor.amber : SleepColor.muted
            )
            TextField(
                "",
                text: Binding(
                    get: { drafts[index] },
                    // Enforced on the way in, not on save: a field that silently
                    // truncates later would show the user a sentence the shield
                    // never displays.
                    set: { drafts[index] = String($0.prefix(SleepLockdownSelection.reasonMaxLength)) }
                ),
                prompt: Text(placeholder(index))
                    .foregroundStyle(SleepColor.faint),
                axis: .vertical
            )
            .font(SleepFont.body(16))
            .foregroundStyle(SleepColor.ink)
            .tint(SleepColor.amber)
            .focused($focused, equals: index)
            .submitLabel(.done)

            // Only appears in the last stretch — a counter sitting there from
            // character one turns writing a sentence into filling a form.
            if remaining(index) <= 15 {
                Text("\(remaining(index))")
                    .font(SleepFont.label(13))
                    .foregroundStyle(remaining(index) == 0 ? SleepColor.amber : SleepColor.faint)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, SleepSpacing.md)
        .frame(minHeight: 52)
    }

    private func remaining(_ index: Int) -> Int {
        SleepLockdownSelection.reasonMaxLength - drafts[index].count
    }

    /// The stem does the work. "I'll know this worked when…" cannot be
    /// answered with "better sleep"; it forces a picture of a specific
    /// morning, which is the thing worth reading on a shield.
    private func placeholder(_ index: Int) -> String {
        switch index {
        case 0: "I'll know this worked when…"
        case 1: "Another reason (optional)"
        default: "One more (optional)"
        }
    }
}

// MARK: - Evening check-in

/// The commitment moment, an hour before bedtime.
///
/// Everything else in the lockdown argues with the 1am self, who did not
/// choose any of this and does not feel bound by it. This screen talks to the
/// person who *does* want it — rational, unhurried, still hours from the
/// craving — and asks them to look at tonight's terms and agree.
///
/// That ordering is the entire trick. A constraint someone accepted while
/// calm is one they later remember accepting; the same constraint discovered
/// at 1am reads as the app doing something to them. It also costs nothing to
/// say yes here, because what they're agreeing to is still hypothetical.
///
/// Deliberately has **no controls that weaken tonight**. It is a review, not a
/// settings screen: the schedule and the app list are reachable from Profile
/// as always, and routing changes through the normal path keeps the
/// held-until-the-window-closes rule (`rescheduleLockdown`) in one place.
struct TonightCheckInView: View {
    var store: SleepStore
    let profile: Profile
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: SleepSpacing.md) {
                Text("Tonight").sectionLabel()
                Text("Bed at \(SleepFormatting.clock(profile.bedtime))")
                    .font(SleepFont.title(28))
                    .foregroundStyle(SleepColor.ink)
                Text("Up at \(SleepFormatting.clock(profile.wakeTime)). \(blockingLine)")
                    .font(SleepFont.body(15))
                    .foregroundStyle(SleepColor.dim)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Their own words, read back while they still agree with them.
            // Someone who re-reads their reason at 10pm is measurably harder to
            // argue out of it at 1am — and if they no longer mean it, this is
            // the calm moment to change it rather than the desperate one.
            if let reason = store.lockReasons.first {
                VStack(alignment: .leading, spacing: SleepSpacing.sm) {
                    Text("You said").sectionLabel()
                    Text("\u{201C}\(reason)\u{201D}")
                        .font(SleepFont.title(18))
                        .foregroundStyle(SleepColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(SleepSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: SleepRadius.lg)
            }

            Spacer()
            Spacer()

            VStack(spacing: SleepSpacing.md) {
                LiquidPrimaryButton(title: "I'm in", systemImage: "checkmark") {
                    onDone()
                }
                Button("Not tonight") {
                    Haptics.heavy()
                    onDone()
                }
                .font(SleepFont.body(15))
                .foregroundStyle(SleepColor.dim)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, SleepSpacing.xxl)
        .padding(.bottom, SleepSpacing.xxl)
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
    }

    /// "Not tonight" changes nothing on purpose — it is an acknowledgement, not
    /// an opt-out. A one-tap "skip tonight" here would be the cleanest bypass
    /// in the whole app, handed to the user at the exact moment they are most
    /// willing to use it later. The real off switch is still in Blocked apps,
    /// where turning it off is a deliberate trip rather than a reflex.

    private var blockingLine: String {
        guard store.willLockDuringSleep else { return "Nothing is blocked tonight." }
        let count = store.lockdownSelectionCount
        return count == 1 ? "1 app locks at bedtime." : "\(count) apps lock at bedtime."
    }
}
