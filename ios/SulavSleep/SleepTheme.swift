import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Color tokens
//
// The palette is the "Warm Pixel Night" system: a warm apartment window looking
// over a quiet city night. Warm amber indoor light against a deep navy sky. No
// purple, no neon, no saturated blues. See DESIGN.md for the full rationale.

extension Color {
    /// Hex convenience, e.g. `Color(hex: 0xF4A261)`.
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

enum SleepColor {
    // Surfaces
    static let background = Color(hex: 0x08111E) // deepest night behind everything
    static let navy = Color(hex: 0x111827)       // deep navy
    static let card = Color(hex: 0x18212F)       // raised surface

    // Sky gradient (top -> bottom), kept close to background so the scene reads calm.
    static let skyTop = Color(hex: 0x0C1728)
    static let skyMid = Color(hex: 0x0A1220)
    static let skyBottom = Color(hex: 0x070D18)

    // Warm accents — the indoor lighting.
    static let amber = Color(hex: 0xF4A261)  // primary accent
    static let gold = Color(hex: 0xE9C46A)   // secondary accent
    static let danger = Color(hex: 0xD96C75)

    // Ink
    static let ink = Color(hex: 0xF5F5F2)     // primary text
    static let dim = Color(hex: 0xB7BDC7)     // secondary text
    static let muted = Color(hex: 0x7A8795)   // muted text
    static let quiet = Color.white.opacity(0.52)
    static let faint = Color.white.opacity(0.30)

    // Lines & glass
    static let hairline = Color.white.opacity(0.06)
    static let border = Color.white.opacity(0.05)
    static let glassFill = Color.white.opacity(0.05)
    static let glassWarm = Color(hex: 0xF4A261, opacity: 0.10)

    // Scene lighting
    static let moon = Color(hex: 0xF4F1E9)
    static let streetGlow = Color(hex: 0xF4A261)
    static let windowGlow = Color(hex: 0xE9C46A)

    static let white = Color.white

    // Sleep mode — pitch black with the day's amber banked down to coals.
    // The asleep screen stays in warm, long-wavelength, low-luminance light
    // (kind to night vision), but the hue is the same indoor-amber family as
    // the rest of the app — not a separate crimson identity. Ember is amber
    // at coal temperature.
    static let sleepBlack = Color(hex: 0x040203)
    static let ember = Color(hex: 0xE0854E)     // timer / primary accent — banked amber
    static let emberDim = Color(hex: 0x9C5530)  // borders / secondary text
    static let emberGlow = Color(hex: 0x7A3A16) // glows / gradient tails
    static let emberDeep = Color(hex: 0x4A2008) // deepest warm shadow
}

// MARK: - Spacing (8pt grid)

enum SleepSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 40
}

enum SleepRadius {
    static let sm: CGFloat = 14
    static let md: CGFloat = 18
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
    static let pill: CGFloat = 999
}

// MARK: - Typography
//
// Editorial neo-grotesk feel per the design brief: light visual weight, highly
// readable, calm. We use the native San Francisco family (`.default` design)
// rather than bundling Inter — SF is Apple's own grotesk and keeps the app
// dependency-free and award-grade native. Weights stay light (regular/medium),
// with `.semibold` reserved for hero moments. Open tracking is applied at call
// sites via `.tracking(...)`.

enum SleepFont {
    /// Hero moments: the greeting name, the sleep timer. Weight ~600.
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    /// Section titles and prominent values. Weight ~500.
    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    /// Body copy. Weight 400.
    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    /// Labels, buttons, small caps. Weight ~500.
    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
}

// MARK: - Tracking helpers

extension View {
    /// Small-caps section label: muted, uppercase, open tracking. The soft
    /// navy shadow is what keeps 12pt caps legible over the *day* city —
    /// small quiet type gets no free contrast from a bright sky, and a
    /// grounded shadow travels with the text across all three scene phases
    /// where a scrim alone can't.
    func sectionLabel() -> some View {
        self
            .font(SleepFont.label(12))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(SleepColor.dim)
            .shadow(color: SleepColor.background.opacity(0.85), radius: 3, y: 1)
    }
}

// MARK: - Sleep-bar hour label
//
// Shared by the Profile record chart and the widget bars (this file compiles
// in both targets), so the chart language stays one system.

/// The hour figure a sleep bar carries. Every label in a chart sits on one
/// shared horizontal plane just above the chart floor — the bar either
/// swallows it, misses it, or catches it mid-glyph. The color splits exactly
/// at the bar's top edge: navy ink where the glyphs sit inside the amber
/// bar, gold where they rise above it into the night. The split is masked at
/// the geometry (two complementary masks, no overlap), so a half-in,
/// half-out number stays legible on both grounds with no threshold guessing.
///
/// Layer it *after* the bar in a bottom-aligned `ZStack`, passing the bar's
/// rendered height.
struct BarHoursLabel: View {
    let text: String
    let fontSize: CGFloat
    /// The label's lift off the chart floor — the shared plane.
    let plane: CGFloat
    let barHeight: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            // The part above the bar, on the night.
            styled(SleepColor.gold)
                .mask(alignment: .bottom) {
                    Rectangle()
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .frame(height: barHeight)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
            // The part inside the bar.
            styled(SleepColor.navy)
                .mask(alignment: .bottom) {
                    Rectangle()
                        .frame(height: barHeight)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
        }
        .accessibilityHidden(true) // charts summarize themselves
    }

    private func styled(_ color: Color) -> some View {
        Text(text)
            .font(SleepFont.label(fontSize))
            .foregroundStyle(color)
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 1)
            .padding(.bottom, plane)
    }
}

// MARK: - Haptics
//
// Strong and universal on buttons: every button in the app knocks `heavy()`
// on tap — wired centrally into the shared components (`GlassIconButton`,
// `LiquidPrimaryButton`, `LiquidSecondaryButton` in LiquidGlass.swift) and
// added by hand at raw `Button`/alert/toggle/stepper call sites. `soft()`
// remains only for non-button cues (drag spring-backs, the sleep screen's
// tap-anywhere reveal); `success()` still marks a night logged/woken.

enum Haptics {
    #if canImport(UIKit)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let successGenerator = UINotificationFeedbackGenerator()
    #endif

    static func prepare() {
        #if canImport(UIKit)
        softGenerator.prepare()
        mediumGenerator.prepare()
        rigidGenerator.prepare()
        heavyGenerator.prepare()
        successGenerator.prepare()
        #endif
    }

    static func soft() {
        #if canImport(UIKit)
        softGenerator.impactOccurred()
        softGenerator.prepare()
        #endif
    }

    /// A heavy, variable-strength tick — used to ratchet the slide-to-sleep
    /// knob and the sleep screen's hold buttons so the night's two commitment
    /// gestures read as genuinely forceful, even through a firm, half-asleep
    /// grip. Heavy (not medium) on purpose: these are the strongest
    /// repeating cues in the app.
    static func tick(intensity: CGFloat) {
        #if canImport(UIKit)
        heavyGenerator.impactOccurred(intensity: max(0, min(1, intensity)))
        heavyGenerator.prepare()
        #endif
    }

    /// A firmer single tap — grab acknowledgments and other sharp accents.
    static func rigid() {
        #if canImport(UIKit)
        rigidGenerator.impactOccurred()
        rigidGenerator.prepare()
        #endif
    }

    /// A single heavy knock — the standard haptic for **every button tap**
    /// in the app.
    static func heavy() {
        #if canImport(UIKit)
        heavyGenerator.impactOccurred()
        heavyGenerator.prepare()
        #endif
    }

    /// Two heavy knocks back to back — the strongest, most unmistakable cue
    /// in the app. Reserved for the instant a commitment threshold is
    /// crossed (the slide completes, a hold completes): it needs to read
    /// through a blanket.
    static func doubleHeavy() {
        #if canImport(UIKit)
        heavyGenerator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            heavyGenerator.impactOccurred()
            heavyGenerator.prepare()
        }
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        successGenerator.notificationOccurred(.success)
        successGenerator.prepare()
        #endif
    }
}
