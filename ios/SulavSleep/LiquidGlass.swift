import SwiftUI

struct LiquidGlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color
    var interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            if interactive {
                content
                    .glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                content
                    .glassEffect(.regular.tint(tint), in: shape)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(SleepColor.hairline, lineWidth: 1)
                }
        }
    }
}

extension View {
    func liquidGlass(
        cornerRadius: CGFloat = SleepRadius.xl,
        tint: Color = SleepColor.glassFill,
        interactive: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassSurface(
                cornerRadius: cornerRadius,
                tint: tint,
                interactive: interactive
            )
        )
    }
}

struct LiquidPrimaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(SleepFont.title(16))
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(LiquidButtonStyle(prominent: true))
    }
}

struct LiquidSecondaryButton: View {
    let title: String
    let value: String?
    let systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SleepSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(SleepFont.label(16))
                if let value {
                    Text("· \(value)")
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
        configuration.label
            .foregroundStyle(prominent ? SleepColor.indigo : SleepColor.white)
            .padding(.horizontal, SleepSpacing.lg)
            .background {
                Capsule(style: .continuous)
                    .fill(prominent ? SleepColor.white : SleepColor.glassFill)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(prominent ? Color.clear : SleepColor.hairline, lineWidth: 1)
            }
            .liquidGlass(
                cornerRadius: SleepRadius.pill,
                tint: prominent ? SleepColor.white.opacity(0.28) : SleepColor.glassFill,
                interactive: true
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct LiquidSheetContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: SleepSpacing.xl) {
            Capsule()
                .fill(SleepColor.hairline)
                .frame(width: 42, height: 5)
            content
        }
        .padding(.horizontal, SleepSpacing.xxl)
        .padding(.top, SleepSpacing.lg)
        .padding(.bottom, SleepSpacing.huge)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: SleepRadius.xl, style: .continuous)
                .fill(SleepColor.bgMid.opacity(0.92))
                .ignoresSafeArea(edges: .bottom)
        }
        .liquidGlass(cornerRadius: SleepRadius.xl)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}

