import SwiftUI
import CoreMotion

// MARK: - Rainy Pixel Night background
//
// A real pixel-art night city (CraftPix, OGA-BY 3.0 — see CREDITS.md) forms the
// static base: sky, moon, stars, clouds, warm-lit skyline. On top of it we keep
// the app's own animated, gyro-parallaxed layers — street-glow bloom, rain,
// drifting dust, and the foreground glass condensation — so the scene
// stays alive and rainy. The pixel art is warm-tinted and darkened so UI text
// stays legible over it. See DESIGN.md.

struct SleepBackground: View {
    /// Kept for call-site compatibility; the pixel scene includes its own moon.
    var showsMoon = true
    /// When false (e.g. an off-screen tab) the animation clock pauses entirely
    /// so we don't pay for redraws nobody sees.
    var isActive = true

    @State private var parallax = ParallaxController()
    @State private var drag: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let p = parallax.isActive ? parallax.offset : drag

                ZStack {
                    SleepColor.background

                    PixelCityBase(size: size, t: t, parallax: p)

                    StreetGlowLayer(t: t, size: size)
                    RainLayer(t: t, size: size)
                    AtmosphereLayer(t: t, size: size)
                    WindowLayer(t: t, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragFallback(size: size))
        }
        .ignoresSafeArea()
        .onAppear { parallax.start() }
        .onDisappear { parallax.stop() }
    }

    private func dragFallback(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !parallax.isActive else { return }
                let nx = Double(value.translation.width / max(size.width, 1) * 2)
                let ny = Double(value.translation.height / max(size.height, 1) * 2)
                drag = CGSize(width: max(-1, min(1, nx)), height: max(-1, min(1, ny)))
            }
            .onEnded { _ in
                withAnimation(.interpolatingSpring(stiffness: 40, damping: 10)) {
                    drag = .zero
                }
            }
    }
}

// MARK: - Pixel-art city base (warm-tinted + darkened for legibility)

private struct PixelCityBase: View {
    let size: CGSize
    let t: TimeInterval
    let parallax: CGSize

    private let layers: [ScrollingPixelLayer.Spec] = [
        .init(assetName: "NightCitySky", speed: 3, xDepth: 2, yDepth: 2, phase: 0.00),
        .init(assetName: "NightCityFarSkyline", speed: 5, xDepth: 4, yDepth: 3, phase: 0.15),
        .init(assetName: "NightCityMidSkyline", speed: 8, xDepth: 7, yDepth: 4, phase: 0.34),
        .init(assetName: "NightCityNearSkyline", speed: 12, xDepth: 10, yDepth: 5, phase: 0.55),
        .init(assetName: "NightCityFrontSkyline", speed: 17, xDepth: 14, yDepth: 6, phase: 0.78),
    ]

    var body: some View {
        ZStack {
            ForEach(layers) { layer in
                ScrollingPixelLayer(spec: layer, size: size, t: t, parallax: parallax)
            }
        }
            .frame(width: size.width, height: size.height)
            .saturation(0.55) // pull the blue toward the warm palette
            .overlay {
                // Warm indoor cast: amber up top, ember low.
                LinearGradient(
                    colors: [SleepColor.amber.opacity(0.22), .clear, SleepColor.crimsonGlow.opacity(0.14)],
                    startPoint: .top, endPoint: .bottom
                )
                .blendMode(.overlay)
            }
            .overlay {
                // Deep-night scrim so headings and buttons stay readable.
                LinearGradient(
                    stops: [
                        .init(color: SleepColor.background.opacity(0.55), location: 0),
                        .init(color: SleepColor.background.opacity(0.18), location: 0.42),
                        .init(color: SleepColor.background.opacity(0.66), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .clipped()
    }
}

private struct ScrollingPixelLayer: View {
    struct Spec: Identifiable {
        var assetName: String
        var speed: CGFloat
        var xDepth: CGFloat
        var yDepth: CGFloat
        var phase: CGFloat

        var id: String { assetName }
    }

    private static let assetAspect: CGFloat = 16.0 / 9.0

    let spec: Spec
    let size: CGSize
    let t: TimeInterval
    let parallax: CGSize

    var body: some View {
        let tileWidth = max(size.height * Self.assetAspect, 1)
        let repeatCount = max(3, Int(ceil(size.width / tileWidth)) + 3)
        let distance = travelDistance(tileWidth: tileWidth)
        let xOffset = -tileWidth - distance + parallax.width * spec.xDepth
        let yOffset = parallax.height * spec.yDepth

        HStack(spacing: 0) {
            ForEach(0..<repeatCount, id: \.self) { _ in
                CachedPixelImage(assetName: spec.assetName)
                    .frame(width: tileWidth, height: size.height)
                    .clipped()
            }
        }
        .frame(width: tileWidth * CGFloat(repeatCount), height: size.height, alignment: .leading)
        .offset(x: xOffset, y: yOffset)
    }

    private func travelDistance(tileWidth: CGFloat) -> CGFloat {
        let raw = (t * Double(spec.speed) + Double(spec.phase * tileWidth))
            .truncatingRemainder(dividingBy: Double(tileWidth))
        return CGFloat(raw)
    }
}

private struct CachedPixelImage: View {
    let assetName: String

    var body: some View {
        #if canImport(UIKit)
        if let image = SleepAssetCache.image(named: assetName) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var fallback: some View {
        Image(assetName)
            .resizable()
            .interpolation(.none)
            .antialiased(false)
    }
}

// MARK: - Parallax controller (gyroscope, spring-smoothed)

@Observable
final class ParallaxController {
    private(set) var offset: CGSize = .zero
    private(set) var isActive = false

    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        isActive = true
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let attitude = data?.attitude else { return }
            let targetX = max(-1, min(1, attitude.roll / 0.6))
            let targetY = max(-1, min(1, (attitude.pitch - 0.5) / 0.6))
            let k = 0.10
            offset.width += (CGFloat(targetX) - offset.width) * k
            offset.height += (CGFloat(targetY) - offset.height) * k
        }
    }

    func stop() {
        guard motion.isDeviceMotionActive else { return }
        motion.stopDeviceMotionUpdates()
        isActive = false
    }
}

// MARK: - Deterministic pseudo-random (stable per element index)

private func hash01(_ i: Int, _ salt: Int = 0) -> Double {
    var x = UInt64(bitPattern: Int64(i &* 374_761_393 &+ salt &* 668_265_263 &+ 1))
    x = (x ^ (x >> 13)) &* 1_274_126_177
    x ^= x >> 16
    return Double(x % 10_000) / 10_000.0
}

// MARK: - Street-light glow (soft orange bloom, slow pulse)

private struct StreetGlowLayer: View {
    let t: TimeInterval
    let size: CGSize

    var body: some View {
        Canvas { context, size in
            let glows: [(CGFloat, CGFloat, CGFloat, Double)] = [
                (0.18, 0.82, 150, 8),
                (0.52, 0.88, 200, 12),
                (0.84, 0.80, 170, 15),
            ]
            for (i, g) in glows.enumerated() {
                let pulse = 1 + 0.05 * sin(t / g.3 + Double(i))
                let radius = g.2 * pulse
                let center = CGPoint(x: size.width * g.0, y: size.height * g.1)
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - radius, y: center.y - radius,
                        width: radius * 2, height: radius * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [SleepColor.streetGlow.opacity(0.14 * pulse), .clear]),
                        center: center, startRadius: 0, endRadius: radius
                    )
                )
            }
        }
        .blendMode(.plusLighter)
    }
}

// MARK: - Rain (three depths)

private struct RainLayer: View {
    let t: TimeInterval
    let size: CGSize

    var body: some View {
        Canvas { context, size in
            drawPass(&context, size: size, count: 40, speed: 190, length: 9, width: 0.8, opacity: 0.10, angle: 0.06, salt: 100)
            drawPass(&context, size: size, count: 30, speed: 320, length: 15, width: 1.1, opacity: 0.16, angle: 0.09, salt: 200)
            drawPass(&context, size: size, count: 10, speed: 520, length: 26, width: 1.8, opacity: 0.30, angle: 0.12, salt: 300, bright: true)
        }
    }

    private func drawPass(
        _ context: inout GraphicsContext,
        size: CGSize, count: Int, speed: Double, length: CGFloat,
        width: CGFloat, opacity: Double, angle: CGFloat, salt: Int, bright: Bool = false
    ) {
        let span = size.height + length + 60
        for i in 0..<count {
            let x0 = hash01(i, salt) * size.width
            let phase = hash01(i, salt + 1)
            let sp = speed * (0.8 + hash01(i, salt + 2) * 0.5)
            var y = (t * sp).truncatingRemainder(dividingBy: Double(span)) + phase * Double(span)
            y = y.truncatingRemainder(dividingBy: Double(span)) - 40
            let top = CGPoint(x: x0 + CGFloat(y) * angle, y: CGFloat(y))
            let bottom = CGPoint(x: top.x + length * angle * 3, y: top.y + length)
            guard hash01(i, salt + 3) > (bright ? 0.35 : 0.08) else { continue }
            var line = Path()
            line.move(to: top)
            line.addLine(to: bottom)
            context.stroke(
                line,
                with: .linearGradient(
                    Gradient(colors: [SleepColor.rain.opacity(0), SleepColor.rain.opacity(opacity)]),
                    startPoint: top, endPoint: bottom
                ),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
            if bright, hash01(i, salt + 4) > 0.7 {
                context.stroke(
                    line,
                    with: .color(.white.opacity(0.18)),
                    style: StrokeStyle(lineWidth: width * 2.4, lineCap: .round)
                )
            }
        }
    }
}

// MARK: - Foreground glass (condensation, sliding droplets, reflection)

private struct WindowLayer: View {
    let t: TimeInterval
    let size: CGSize

    var body: some View {
        Canvas { context, size in
            // Condensation speckle near the top corners.
            for i in 0..<70 {
                let side = hash01(i, 41) > 0.5 ? 0.0 : 1.0
                let x = (side == 0 ? hash01(i, 42) * 0.3 : 0.7 + hash01(i, 42) * 0.3) * size.width
                let y = hash01(i, 43) * size.height * 0.42
                let r = 0.6 + hash01(i, 44) * 1.2
                let shimmer = 0.02 + 0.03 * (0.5 + 0.5 * sin(t * 0.5 + Double(i)))
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(.white.opacity(shimmer))
                )
            }

            // Droplets sliding down the glass, each leaving a faint trail.
            for i in 0..<5 {
                let x = (0.14 + hash01(i, 51) * 0.72) * size.width
                let period = 14.0 + hash01(i, 52) * 16
                let progress = ((t / period) + hash01(i, 53)).truncatingRemainder(dividingBy: 1)
                let y = CGFloat(progress) * (size.height + 40) - 20
                let dropLen = 10 + hash01(i, 54) * 16

                var trail = Path()
                trail.move(to: CGPoint(x: x, y: y - dropLen))
                trail.addLine(to: CGPoint(x: x, y: y))
                context.stroke(trail, with: .color(.white.opacity(0.06)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 4.4)),
                    with: .color(.white.opacity(0.14))
                )
            }
        }
    }
}

// MARK: - Floating atmosphere (faint drifting dust)

private struct AtmosphereLayer: View {
    let t: TimeInterval
    let size: CGSize

    var body: some View {
        Canvas { context, size in
            for i in 0..<26 {
                let baseX = hash01(i, 61) * size.width
                let baseY = hash01(i, 62) * size.height
                let x = baseX + CGFloat(sin(t * (0.05 + hash01(i, 63) * 0.08) + Double(i)) * 18)
                let y = baseY + CGFloat(cos(t * (0.04 + hash01(i, 64) * 0.06) + Double(i)) * 12)
                let r = 0.6 + hash01(i, 65) * 1.4
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(SleepColor.gold.opacity(0.03 + hash01(i, 66) * 0.03))
                )
            }
        }
        .blendMode(.plusLighter)
    }
}
