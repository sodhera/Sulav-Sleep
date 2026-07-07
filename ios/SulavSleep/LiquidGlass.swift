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
/// A small circular icon action — the Profile gear, the settings-sheet close
/// ✕, the onboarding back chevron. These all share one size so they read as
/// the same control language wherever they appear.
///
/// The reaction is driven by a **custom `ButtonStyle`** (`GlassCircleButtonStyle`),
/// not `.buttonStyle(.plain)` + a bare `.glassEffect(.interactive())`. That
/// earlier structure looked right but felt dead: the plain button's own
/// gesture recognizer swallows the touch, so the interactive glass never
/// receives the press events and nothing deforms. A `ButtonStyle` instead
/// *owns* `configuration.isPressed`, so it can guarantee a visible reaction —
/// here a springy squish (a real size change on press, over-damped so it
/// bounces back like jelly) layered on top of the genuine `.interactive()`
/// Liquid Glass. Note these are *buttons*: they squish on press and settle,
/// they do not stretch to follow a dragging finger — that gel-follow belongs
/// to draggable controls like the slide-to-sleep knob, not to a tap target.
struct GlassIconButton: View {
    let systemImage: String
    var size: CGFloat = 56
    var iconSize: CGFloat = 20
    var tint: Color = SleepColor.dim
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .buttonStyle(GlassCircleButtonStyle(size: size))
    }
}

/// Circular glass button chrome with a guaranteed springy press. Real
/// interactive Liquid Glass on iOS 26+, `.ultraThinMaterial` circle pre-26;
/// both get the same jelly squish so the control feels alive everywhere,
/// including where the OS doesn't render the glass deformation itself.
private struct GlassCircleButtonStyle: ButtonStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .contentShape(.circle)
            .modifier(GlassCircleSurface())
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.42), value: configuration.isPressed)
    }
}

private struct GlassCircleSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(SleepColor.border, lineWidth: 1) }
        }
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

/// Warm, primary action. Amber Liquid Glass, deep-navy ink, soft glow. On
/// iOS 26+ this is an amber-tinted **interactive** glass capsule driven by a
/// custom `ButtonStyle` (`GlassCapsuleButtonStyle`) — so besides the glass's
/// own touch morph it gets a guaranteed springy press from
/// `configuration.isPressed`. (A plain button + bare `.glassEffect(
/// .interactive())` swallows the touch in its own gesture, so the glass never
/// sees the press and the button feels dead — the `ButtonStyle` owns the
/// press state instead.) The tint is a bright amber so the capsule still
/// never melts into the pixel skyline (see DESIGN.md). Pre-26 keeps the
/// hand-drawn amber→gold gradient capsule.
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
            Button(action: action) { labelContent }
                .buttonStyle(GlassCapsuleButtonStyle(tint: SleepColor.amber))
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
/// On iOS 26+ this is an untinted interactive glass capsule via the same
/// `GlassCapsuleButtonStyle` as the primary (no tint), so its press feels the
/// same.
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
            Button(action: action) { labelContent }
                .buttonStyle(GlassCapsuleButtonStyle(tint: nil))
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

/// iOS 26+ capsule chrome shared by every full-width capsule action in the
/// app: interactive Liquid Glass (tinted when `tint` is set) plus a springy
/// press driven by `configuration.isPressed`, so the button reacts even
/// where the OS doesn't render the glass's own touch deformation. Used by
/// `LiquidPrimaryButton`/`LiquidSecondaryButton` here and by sleep mode's
/// "Back to sleep" (`SleepModeView.swift`), which needs its own ember-palette
/// label rather than these two components' day-palette defaults. Only used
/// inside an `if #available(iOS 26.0, *)` branch.
@available(iOS 26.0, *)
struct GlassCapsuleButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        let glass: Glass = tint.map { .regular.tint($0).interactive() } ?? .regular.interactive()
        return configuration.label
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(shape)
            .glassEffect(glass, in: shape)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.58), value: configuration.isPressed)
    }
}

/// Pre-iOS-26 fallback chrome for the two action buttons above. On 26+ the
/// `GlassCapsuleButtonStyle` owns the chrome instead.
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
