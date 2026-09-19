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
// **DM Sans** (SIL Open Font License — see `CREDITS.md`), bundled as its
// variable font and driven on both of its axes.
//
// The weight axis replaces what `.system(weight:)` used to do. The **optical
// size** axis is the part that matters and the part a naive integration
// throws away: DM Sans ships with `opsz` defaulting to 9, so pulling it in
// with `Font.custom(_:size:)` renders the *text* cut of the typeface at every
// size — noticeably loose and wide at a 46pt hero number. Mapping `opsz` to
// the point size gets the display cut where it belongs, which is most of why
// the face looks right at the top of a screen and still reads at 12pt.
//
// Everything routes through `SleepFont`, so this is the single place the app's
// type is decided; call sites are unchanged. `Font(uiFont)` does not
// participate in Dynamic Type, but neither did the fixed-size `.system(size:)`
// calls it replaces, so nothing regressed — it is still worth fixing one day.
//
// The font is bundled in **two** targets: the app and the widget extension,
// which compiles this file too. An app extension has its own bundle and does
// not inherit the host's registered fonts.

enum SleepFont {
    /// Hero moments: the greeting name, the sleep timer.
    static func hero(_ size: CGFloat) -> Font { dmSans(size, weight: 600) }

    /// Section titles and prominent values.
    static func title(_ size: CGFloat) -> Font { dmSans(size, weight: 500) }

    /// Body copy.
    static func body(_ size: CGFloat) -> Font { dmSans(size, weight: 400) }

    /// Labels, buttons, small caps.
    static func label(_ size: CGFloat) -> Font { dmSans(size, weight: 500) }

    /// The one italic in the app (the phone slider's "Be honest."). Uses the
    /// real italic cut rather than letting the system shear the roman.
    static func bodyItalic(_ size: CGFloat) -> Font {
        dmSans(size, weight: 400, italic: true)
    }
}

#if canImport(UIKit)
/// Builds a DM Sans instance at a given weight and optical size.
///
/// Falls back to the system face if the bundle is missing the font or the
/// descriptor fails, so a packaging mistake degrades to Apple's grotesk
/// instead of crashing — but `SleepTypeface.isAvailable` exists so a build can
/// *assert* the real thing loaded, because silent fallback looks exactly like
/// "the font change didn't apply".
private func dmSans(_ size: CGFloat, weight: CGFloat, italic: Bool = false) -> Font {
    guard let uiFont = SleepTypeface.uiFont(size: size, weight: weight, italic: italic) else {
        return .system(size: size, weight: systemWeight(weight), design: .default)
    }
    return Font(uiFont)
}

private func systemWeight(_ weight: CGFloat) -> Font.Weight {
    switch weight {
    case ..<450: .regular
    case ..<550: .medium
    case ..<650: .semibold
    default: .bold
    }
}

enum SleepTypeface {
    /// PostScript names of the bundled variable fonts. These are *not*
    /// "DM Sans" — the family name carries the default optical size, so the
    /// roman registers as `DMSans-9ptRegular`. Getting this wrong is the
    /// classic silent fallback to San Francisco.
    static let roman = "DMSans-9ptRegular"
    static let italic = "DMSans-9ptItalic"

    /// Variation axis tags as their four-character codes.
    private static let opszAxis: UInt32 = 0x6F70_737A   // 'opsz'
    private static let wghtAxis: UInt32 = 0x7767_6874   // 'wght'

    /// The `opsz` axis range DM Sans actually defines. Sizes outside it clamp.
    private static let opticalRange: ClosedRange<CGFloat> = 9...40

    static func uiFont(size: CGFloat, weight: CGFloat, italic: Bool) -> UIFont? {
        let optical = min(max(size, opticalRange.lowerBound), opticalRange.upperBound)
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: italic ? Self.italic : roman,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [
                opszAxis: optical,
                wghtAxis: weight
            ]
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        // UIFont(descriptor:size:) never returns nil: an unknown name yields
        // the system face instead, which is the failure we actually care
        // about catching.
        return font.familyName.contains("DM Sans") ? font : nil
    }

    /// Whether the bundled typeface registered. Checked once at launch in
    /// DEBUG so a packaging regression is loud rather than invisible.
    static var isAvailable: Bool {
        uiFont(size: 17, weight: 400, italic: false) != nil
    }
}
#else
private func dmSans(_ size: CGFloat, weight: CGFloat, italic: Bool = false) -> Font {
    .system(size: size, weight: weight >= 550 ? .semibold : (weight >= 450 ? .medium : .regular))
}
#endif

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

// MARK: - Rising z's
//
// The app icon's ZZZ, alive. `RisingZs` began as the sleep screen's one
// ornament (ember z's off the night sloth's head) and is shared here so the
// onboarding/auth brand mark (`SlothBrandMark` in OnboardingView.swift —
// app target only, since it needs `CityPhase` and the Home sloth art) can
// run the same chain in gold. Each z drifts
// up the same diagonal, swells a touch, and fades out; three staggered
// cycles mean at most two are ever visible, so it reads as slow breathing
// rather than motion. Under Reduce Motion the chain freezes into the icon's
// static diagonal.

struct RisingZs: View {
    /// `emberDim` on the OLED sleep screen; gold on the brand mark, where
    /// the z's stand in for the icon's gold ZZZ.
    var color: Color = SleepColor.emberDim
    /// Uniform scale on the glyphs and their travel. 1 is the sleep screen's
    /// full-size chain (tuned for a 300pt sloth).
    var scale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if reduceMotion {
                ForEach(Array([12.0, 14.0, 16.0].enumerated()), id: \.offset) { i, size in
                    Text("z")
                        .font(.system(size: size * scale, weight: .semibold))
                        .foregroundStyle(color)
                        .opacity(0.2 + Double(i) * 0.11)
                        .offset(x: CGFloat(i) * 11 * scale, y: CGFloat(i) * -19 * scale)
                }
            } else {
                RisingZ(color: color, scale: scale, startDelay: 0)
                RisingZ(color: color, scale: scale, startDelay: 2.5)
                RisingZ(color: color, scale: scale, startDelay: 5.0)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// One z of the chain. The z is *always* in the hierarchy (invisible between
/// rides — a conditionally-inserted view would never run its start-delay
/// task while empty); each ride is a one-shot `keyframeAnimator` fired by a
/// trigger, and a task loop beats that trigger every `cycle` seconds, first
/// fire delayed by `startDelay` so the three z's hold their stagger forever.
private struct RisingZ: View {
    let color: Color
    let scale: CGFloat
    let startDelay: Double

    @State private var beat = 0

    private struct Phase {
        var rise: CGFloat = 0
        var drift: CGFloat = 0
        var scale: CGFloat = 0.85
        var opacity: Double = 0
    }

    /// Seconds a z is visibly rising, and the full loop length.
    private static let active: Double = 4.5
    private static let cycle: Double = 7.5

    var body: some View {
        Text("z")
            .font(.system(size: 15 * scale, weight: .semibold))
            .foregroundStyle(color)
            .keyframeAnimator(initialValue: Phase(), trigger: beat) { view, phase in
                view
                    .scaleEffect(phase.scale)
                    .opacity(phase.opacity)
                    .offset(x: phase.drift, y: phase.rise)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    CubicKeyframe(0.55, duration: 1.1)
                    LinearKeyframe(0.46, duration: 1.6)
                    CubicKeyframe(0, duration: Self.active - 2.7)
                }
                KeyframeTrack(\.rise) {
                    CubicKeyframe(-46 * scale, duration: Self.active)
                }
                KeyframeTrack(\.drift) {
                    CubicKeyframe(14 * scale, duration: Self.active)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.15, duration: Self.active)
                }
            }
            .task {
                if startDelay > 0 {
                    guard (try? await Task.sleep(for: .seconds(startDelay))) != nil else { return }
                }
                while !Task.isCancelled {
                    beat &+= 1
                    guard (try? await Task.sleep(for: .seconds(Self.cycle))) != nil else { return }
                }
            }
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
