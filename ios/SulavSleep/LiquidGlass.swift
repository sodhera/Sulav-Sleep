import SwiftUI

// Centralized Liquid Glass behavior. Native `glassEffect` on iOS 26+, with a
// `.ultraThinMaterial` fallback that keeps the same shape and hairline border.
// Glass here reads like slightly fogged night-window glass: light blur, subtle
// transparency, warm reflection, thin border. See DESIGN.md.

struct LiquidGlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color
    var interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                content.glassEffect(.regular.tint(tint), in: shape)
            }
        } else {
            content
                // Tint wash in front of the material so the fallback honors
                // the same warm/neutral tints the real glass gets on 26+.
                .background(tint, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.stroke(SleepColor.border, lineWidth: 1) }
        }
    }
}

/// Groups sibling glass shapes so iOS 26 renders them as one set — nearby
/// glass samples/blends together and can merge as elements move, which is
/// how Apple intends multiple Liquid Glass elements to coexist. Pre-26 it
/// is a plain passthrough. Wrap exactly one layout view (an HStack/VStack),
/// never loose siblings.
struct LiquidGlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    func liquidGlass(
        cornerRadius: CGFloat = SleepRadius.xl,
        tint: Color = SleepColor.glassFill,
        interactive: Bool = false
    ) -> some View {
        modifier(LiquidGlassSurface(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

// MARK: - Icon buttons

/// A small circular icon action — the Profile gear, the settings-sheet close
/// ✕, the onboarding back chevron. These all share one size so they read as
/// the same control language wherever they appear.
///
/// On iOS 26+ this is a genuine system Liquid Glass button
/// (`.buttonStyle(.glass)` + `.buttonBorderShape(.circle)`), which is Apple's
/// own purpose-built button chrome — it gets the real squish/morph/highlight
/// press choreography for free. Decorating an arbitrary `Button` with
/// `.glassEffect(.interactive())` from the outside (the previous approach)
/// renders the right *material* but two independent gesture recognizers (the
/// button's tap gesture and the glass's own touch-tracking) don't coordinate
/// as tightly as the dedicated style, which is why it read as flat rather
/// than "liquid." Pre-26 falls back to the material glass surface with a
/// matching press scale, since that path has no built-in interaction physics
/// to lean on.
///
/// Sizing: on 26+ the *label* is framed to `size` minus the style's own
/// content insets, so the drawn circle lands at ~`size` while keeping the
/// style's natural chrome (an earlier revision framed the button itself,
/// which clamped Apple's chrome smaller than the system draws it anywhere
/// else — the buttons read undersized next to other iOS 26 apps). `size` is
/// the full circle diameter on both paths.
struct GlassIconButton: View {
    let systemImage: String
    var size: CGFloat = 56
    var iconSize: CGFloat = 20
    var tint: Color = SleepColor.dim
    let action: () -> Void

    /// The glass style's default circular content insets, measured on iOS 26
    /// (screenshot-verified: a 18pt label renders a ~30pt circle).
    /// Label frame + these insets = the rendered circle.
    private static let glassInsets: CGFloat = 12

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(
                        width: max(iconSize, size - Self.glassInsets),
                        height: max(iconSize, size - Self.glassInsets)
                    )
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        } else {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
            }
            .buttonStyle(GlassIconButtonFallbackStyle())
        }
    }
}

private struct GlassIconButtonFallbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .liquidGlass(cornerRadius: SleepRadius.pill, interactive: true)
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Grouped glass rows (settings surfaces)

/// A grouped glass container for a functional cluster of control rows —
/// the settings-surface pattern. Rows inside separate themselves with
/// `GlassRowDivider`; the group provides the shared glass, border, and
/// horizontal inset. Never nested.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, SleepSpacing.lg)
        // No manual border: real glass draws its own edge highlight on 26+,
        // and the fallback strokes a hairline inside `liquidGlass` itself.
        .liquidGlass(cornerRadius: SleepRadius.lg)
    }
}

/// Hairline between rows in a `GlassGroup`.
struct GlassRowDivider: View {
    var body: some View {
        Rectangle().fill(SleepColor.hairline).frame(height: 1)
    }
}

/// One row inside a `GlassGroup`: a small tinted icon chip, a short title,
/// and an optional quiet trailing value + chevron. Kept to one line — rows
/// name things, they don't explain them.
struct GlassRow: View {
    let icon: String
    var iconColor: Color = SleepColor.amber
    let title: String
    var titleColor: Color = SleepColor.ink
    var value: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: SleepSpacing.md) {
            GlassRowIcon(icon: icon, color: iconColor)

            Text(title)
                .font(SleepFont.body(16))
                .foregroundStyle(titleColor)

            Spacer(minLength: SleepSpacing.md)

            if let value {
                Text(value)
                    .font(SleepFont.body(15))
                    .foregroundStyle(SleepColor.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SleepColor.faint)
            }
        }
        .padding(.vertical, SleepSpacing.md)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// The leading icon chip for a `GlassRow` — the symbol sits in a soft
/// rounded square tinted from its own color, so rows scan by glyph first.
struct GlassRowIcon: View {
    let icon: String
    var color: Color = SleepColor.amber

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(0.12))
            }
    }
}

// MARK: - Buttons

/// Warm, primary action. Amber-tinted prominent Liquid Glass, deep-navy ink,
/// soft glow. On iOS 26+ this is Apple's own `.glassProminent` button style
/// tinted amber — the system's purpose-built primary glass button, with its
/// real press choreography — rather than an opaque gradient capsule painted
/// under a glass layer (which muted the material into a flat panel). Pre-26
/// keeps the hand-drawn amber→gold capsule.
struct LiquidPrimaryButton: View {
    let title: String
    var systemImage: String?
    /// When true, the label is swapped for a centered spinner in place — the
    /// pill keeps its size so the button doesn't jump. Matches the provider
    /// buttons' in-button loading style.
    var isLoading: Bool
    var action: () -> Void

    init(title: String, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                labelContent
                    // The style adds ~14pt of its own vertical insets
                    // (measured on iOS 26), so a 46pt label lands the button
                    // at the app's ~60pt primary-action height.
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(SleepColor.amber)
            .shadow(color: SleepColor.amber.opacity(0.30), radius: 18, y: 7)
        } else {
            Button(action: action) {
                labelContent
                    .frame(maxWidth: .infinity, minHeight: 58)
            }
            .buttonStyle(LiquidButtonStyle(prominent: true))
        }
    }

    private var labelContent: some View {
        ZStack {
            Label {
                Text(title).font(SleepFont.label(16)).tracking(0.2)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .opacity(isLoading ? 0 : 1)

            if isLoading {
                ProgressView().tint(SleepColor.background)
            }
        }
        .foregroundStyle(SleepColor.background)
    }
}

/// Quiet, secondary action. Subtle glass, ink text, optional trailing value.
/// On iOS 26+ this is Apple's `.glass` button style — untinted system glass.
struct LiquidSecondaryButton: View {
    let title: String
    var value: String?
    var systemImage: String?
    var action: () -> Void

    init(title: String, value: String? = nil, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                labelContent
                    // Same 46 + ~14pt style insets math as the primary, so
                    // the two action heights stay identical.
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        } else {
            Button(action: action) {
                labelContent
                    .frame(maxWidth: .infinity, minHeight: 58)
            }
            .buttonStyle(LiquidButtonStyle(prominent: false))
        }
    }

    private var labelContent: some View {
        HStack(spacing: SleepSpacing.sm) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title).font(SleepFont.label(16))
            if let value {
                Text(value)
                    .foregroundStyle(SleepColor.quiet)
                    .font(SleepFont.body(15))
            }
        }
        .foregroundStyle(SleepColor.ink)
    }
}

/// Pre-iOS-26 fallback chrome for the two action buttons above. On 26+ the
/// system `.glassProminent` / `.glass` styles own the chrome instead.
struct LiquidButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(prominent ? SleepColor.background : SleepColor.ink)
            .padding(.horizontal, SleepSpacing.lg)
            .background {
                Capsule(style: .continuous)
                    .fill(prominent ? AnyShapeStyle(warmFill) : AnyShapeStyle(SleepColor.glassFill))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(prominent ? Color.white.opacity(0.18) : SleepColor.border, lineWidth: 1)
            }
            .liquidGlass(
                cornerRadius: SleepRadius.pill,
                tint: prominent ? SleepColor.glassWarm : SleepColor.glassFill,
                interactive: true
            )
            .shadow(
                color: SleepColor.amber.opacity(prominent ? (pressed ? 0.18 : 0.34) : 0),
                radius: pressed ? 10 : 20,
                y: pressed ? 3 : 8
            )
            .scaleEffect(pressed ? 0.98 : 1)
            .opacity(pressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.18), value: pressed)
    }

    private var warmFill: LinearGradient {
        LinearGradient(
            colors: [SleepColor.gold, SleepColor.amber],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
