import ManagedSettings
import ManagedSettingsUI
import UIKit

// ShieldConfigurationExtension: customizes the overlay shown when the user
// tries to open a shielded app during sleep lockdown. Replaces Apple's generic
// "Screen Time Limit" card with the SleepBlock brand mark — the sleeping
// night sloth on its warm halo with the gold rising-z chain alive above it —
// and copy encouraging the user to go back to bed.
//
// This extension runs in its own sandboxed process. It cannot import the main
// app's SwiftUI views or asset catalog — only ManagedSettings types plus
// whatever resources are bundled into this target (ShieldSloth.png, a
// downsized copy of HomeSlothNightBlink). The shield UI itself is rendered by
// the system from a static ShieldConfiguration, so the ZZZ animation is baked
// into the icon as an animated UIImage: the full 7.5s RisingZs cycle
// (SleepTheme.swift) pre-rendered into frames. Keep the frame budget modest —
// shield config extensions live under a tight jetsam limit, and a killed
// extension falls back to Apple's generic gray shield.

class ShieldConfigProvider: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfig(noun: "This app")
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        makeConfig(noun: "This app")
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfig(noun: "This site")
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        makeConfig(noun: "This site")
    }

    // MARK: - Palette (mirrors SleepColor in SleepTheme.swift)

    private static let amber = UIColor(red: 0xF4 / 255.0, green: 0xA2 / 255.0, blue: 0x61 / 255.0, alpha: 1)
    private static let gold = UIColor(red: 0xE9 / 255.0, green: 0xC4 / 255.0, blue: 0x6A / 255.0, alpha: 1)
    private static let ink = UIColor(red: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF2 / 255.0, alpha: 1)
    private static let dim = UIColor(red: 0xB7 / 255.0, green: 0xBD / 255.0, blue: 0xC7 / 255.0, alpha: 1)
    private static let faint = UIColor(red: 0x7A / 255.0, green: 0x84 / 255.0, blue: 0x94 / 255.0, alpha: 1)
    private static let bg = UIColor(red: 0.03, green: 0.07, blue: 0.12, alpha: 1) // ~#08111E

    // MARK: - Phase-aware shield configuration

    /// Whether the current lockdown is the pre-sleep nudge or the firm active
    /// session lock.
    private var isPresleep: Bool {
        SleepLockdownSelection.currentPhase() == .presleep
    }

    /// Hours and minutes until the alarm — "5h 48m until your alarm".
    ///
    /// This replaced "42 minutes past bedtime", and the swap is the point: one
    /// is a fact about the pain arriving in the morning, the other is a
    /// scolding about a decision already made. Someone standing at a block
    /// screen at 1am has fully priced in that they are up late; what they have
    /// not done is the subtraction.
    ///
    /// It lives in the title slot because that is the only way to make it bold:
    /// `ShieldConfiguration.Label` carries a string and a colour and nothing
    /// else, so there is no way to emphasise part of the subtitle. Nil when
    /// wake time isn't mirrored yet (no lockdown scheduled on this install), or
    /// once the alarm has already gone — a session that outslept its wake time
    /// keeps the shield up, and counting down to *tomorrow's* alarm there would
    /// turn a 10-minute lie-in into "23h 50m". The shield then keeps its
    /// written title, whose subtitle already says asleep until you wake.
    private var alarmTitle: String? {
        guard let minutes = SleepLockdownSelection.minutesUntilWakeTonight(), minutes >= 1 else { return nil }
        return "\(Self.duration(minutes)) until your alarm"
    }

    /// "5 minutes" / "1 minute" / "1h 15m" / "2h".
    private static func duration(_ minutes: Int) -> String {
        if minutes < 60 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// The secondary button, resolved from the shared escape state so this and
    /// `ShieldActionHandler` can't disagree about what a tap means.
    ///
    /// Never nil any more. A shield with no way out at all is a dead end, and
    /// the only exit left from a dead end is deleting SleepBlock — which takes
    /// the blocking with it, permanently. The door is deliberately cheap to
    /// ask for and slow to open; see `SleepLockdownSelection.doorRequestedKey`.
    private func secondaryLabel(for escape: SleepLockdownSelection.Escape) -> ShieldConfiguration.Label {
        switch escape {
        case .snooze:
            return .init(text: "\(SleepLockdownSelection.snoozeMinutes) more minutes", color: Self.dim)
        case .doorClosed:
            return .init(text: "I need \(SleepLockdownSelection.doorMinutes) minutes", color: Self.dim)
        case .doorWaiting(let seconds):
            // Informational — the tap does nothing. The wait *is* the feature:
            // a craving fades in about a minute, and most people put the phone
            // down here rather than come back.
            return .init(text: "Unlocks in \(seconds)s", color: Self.faint)
        case .doorReady:
            return .init(text: "Unlock \(SleepLockdownSelection.doorMinutes) minutes", color: Self.dim)
        }
    }

    private func makeConfig(noun: String) -> ShieldConfiguration {
        // Counting happens here because this method runs exactly when the user
        // reaches for a blocked app — the measurement is free, on a screen that
        // has to render anyway. Debounced inside `recordReach`, since the
        // system can ask for a configuration more than once per launch.
        let reach = SleepLockdownSelection.recordReach()
        let escape = SleepLockdownSelection.currentEscape()
        // Their own sentence, rotated per reach, beats anything we could write:
        // there is no app to be annoyed at in it. Falls back to our copy until
        // they've written one.
        let reason = SleepLockdownSelection.reasonForReach(reach)

        if isPresleep {
            let alarm = alarmTitle
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialDark,
                backgroundColor: Self.bg,
                icon: Self.brandMarkIcon ?? UIImage(systemName: "moon.zzz.fill"),
                title: ShieldConfiguration.Label(
                    text: alarm ?? "Time for bed",
                    color: Self.ink
                ),
                subtitle: ShieldConfiguration.Label(
                    text: reason ?? (alarm == nil
                        ? "Put your phone down and head to bed."
                        : "Time for bed."),
                    color: Self.dim
                ),
                primaryButtonLabel: ShieldConfiguration.Label(
                    text: "Sleep Now",
                    color: .black
                ),
                primaryButtonBackgroundColor: Self.amber,
                // The escape hatch takes the quiet secondary slot, never the
                // amber one — a shield whose loudest control is "not yet"
                // argues against itself.
                secondaryButtonLabel: secondaryLabel(for: escape)
            )
        } else {
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialDark,
                backgroundColor: Self.bg,
                icon: Self.brandMarkIcon ?? UIImage(systemName: "moon.zzz.fill"),
                title: ShieldConfiguration.Label(
                    text: alarmTitle ?? "Time to sleep",
                    color: Self.ink
                ),
                subtitle: ShieldConfiguration.Label(
                    text: reason ?? "\(noun) is asleep until you wake.",
                    color: Self.dim
                ),
                primaryButtonLabel: ShieldConfiguration.Label(
                    text: "Good night",
                    color: .black
                ),
                primaryButtonBackgroundColor: Self.amber,
                // The active-phase shield used to ship with no secondary button
                // at all, on the reasoning that snoozing out of a session you
                // deliberately started makes lockdown meaningless. That still
                // holds for the *snooze* — `currentEscape` won't offer one here.
                // The door is different: it is the phase where someone is
                // furthest from morning and most likely to reach for the
                // uninstall button, and "wait six hours or delete the app" is
                // not a choice worth forcing.
                secondaryButtonLabel: secondaryLabel(for: escape)
            )
        }
    }

    // MARK: - Brand mark icon

    /// The onboarding brand mark (`SlothBrandMark`) recreated for the shield:
    /// the night sloth over its amber halo, with the icon's gold ZZZ rising —
    /// one full `RisingZs` cycle baked into an animated UIImage. Built once
    /// per extension process and reused across shields.
    private static let brandMarkIcon: UIImage? = makeBrandMarkIcon()

    private static func makeBrandMarkIcon() -> UIImage? {
        guard let slothPath = Bundle(for: ShieldConfigProvider.self)
                .path(forResource: "ShieldSloth", ofType: "png"),
              let sloth = UIImage(contentsOfFile: slothPath) else { return nil }

        // Composition mirrors SlothBrandMark (OnboardingView.swift): the
        // sloth (art is 5:3) sits at the bottom of a square canvas, the z's
        // ride the headroom above. zScale 0.62 matches the welcome screen's
        // mark — small marks keep oversized z's so the chain stays legible.
        let side: CGFloat = 84
        let zScale: CGFloat = 0.62
        let slothSize = CGSize(width: side, height: side * 0.6)
        let slothOrigin = CGPoint(x: 0, y: side - slothSize.height)

        // RisingZs timing (SleepTheme.swift): three z's staggered 2.5s over a
        // 7.5s cycle, each active 4.5s. ~5 fps is enough for drift this slow;
        // more frames risk the extension's memory ceiling. The 1.2s phase
        // shift makes frame 0 — the static fallback if the shield ever
        // declines to animate — show the chain mid-breath, not empty.
        let cycle = 7.5
        let frameCount = 38
        let phaseShift = 1.2

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)

        var frames: [UIImage] = []
        for frame in 0..<frameCount {
            let now = (Double(frame) / Double(frameCount)) * cycle + phaseShift
            frames.append(renderer.image { _ in
                drawHalo(around: CGRect(origin: slothOrigin, size: slothSize))
                sloth.draw(in: CGRect(origin: slothOrigin, size: slothSize))
                for delay in [0.0, 2.5, 5.0] {
                    let t = (now - delay).truncatingRemainder(dividingBy: cycle)
                    drawZ(atCycleTime: t < 0 ? t + cycle : t,
                          base: CGPoint(x: slothOrigin.x + side * 0.22, y: slothOrigin.y),
                          zScale: zScale)
                }
            })
        }
        return UIImage.animatedImage(with: frames, duration: cycle)
    }

    /// The warm halo that seats the sloth — SlothBrandMark's blurred amber
    /// ellipse approximated as an elliptical radial gradient (CoreGraphics
    /// has no cheap gaussian blur).
    private static func drawHalo(around rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let colors = [amber.withAlphaComponent(0.18).cgColor,
                      amber.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.translateBy(x: rect.midX, y: rect.midY)
        // Squash the circular gradient into the ellipse's 5:3-ish proportions.
        ctx.scaleBy(x: 1, y: 0.68)
        ctx.drawRadialGradient(gradient,
                               startCenter: .zero, startRadius: 0,
                               endCenter: .zero, endRadius: rect.width * 0.58,
                               options: [])
        ctx.restoreGState()
    }

    /// One z of the chain at `t` seconds into its cycle, replicating the
    /// RisingZ keyframes: fade in to 0.55 (1.1s), settle to 0.46 (1.6s),
    /// fade out (1.8s), while rising 46pt·scale, drifting 14pt·scale, and
    /// swelling 0.85 → 1.15 across the 4.5s active window.
    private static func drawZ(atCycleTime t: Double, base: CGPoint, zScale: CGFloat) {
        let active = 4.5
        guard t >= 0, t < active else { return }

        let opacity: Double
        if t < 1.1 {
            opacity = 0.55 * smooth(t / 1.1)
        } else if t < 2.7 {
            opacity = 0.55 - 0.09 * ((t - 1.1) / 1.6)
        } else {
            opacity = 0.46 * (1 - smooth((t - 2.7) / 1.8))
        }

        let travel = CGFloat(smooth(t / active))
        let rise = -46 * zScale * travel
        let drift = 14 * zScale * travel
        let glyphScale = 0.85 + 0.30 * travel

        let font = UIFont.systemFont(ofSize: 15 * zScale * glyphScale, weight: .semibold)
        let z = NSAttributedString(string: "z", attributes: [
            .font: font,
            .foregroundColor: gold.withAlphaComponent(opacity),
        ])
        z.draw(at: CGPoint(x: base.x + drift, y: base.y + rise))
    }

    /// Smoothstep stand-in for SwiftUI's CubicKeyframe interpolation.
    private static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
