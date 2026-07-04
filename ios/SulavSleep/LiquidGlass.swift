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
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.stroke(SleepColor.border, lineWidth: 1) }
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

// MARK: - Buttons

/// Warm, primary action. Amber gradient fill, deep-navy ink, soft glow.
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
        Button(action: action) {
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
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(LiquidButtonStyle(prominent: true))
    }
}

/// Quiet, secondary action. Subtle glass, ink text, optional trailing value.
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
        Button(action: action) {
            HStack(spacing: SleepSpacing.sm) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(SleepFont.label(16))
                if let value {
                    Text(value)
                        .foregroundStyle(SleepColor.quiet)
                        .font(SleepFont.body(15))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(LiquidButtonStyle(prominent: false))
    }
}

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
