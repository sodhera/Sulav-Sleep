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
    private static let bg = UIColor(red: 0.03, green: 0.07, blue: 0.12, alpha: 1) // ~#08111E

    private func makeConfig(noun: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: Self.bg,
            icon: Self.brandMarkIcon ?? UIImage(systemName: "moon.zzz.fill"),
            title: ShieldConfiguration.Label(
                text: "Time to sleep",
                color: Self.ink
            ),
            subtitle: ShieldConfiguration.Label(
                text: "\(noun) is asleep until you wake. Head back to bed.",
                color: Self.dim
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Good night",
                color: .black
            ),
            primaryButtonBackgroundColor: Self.amber
        )
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
