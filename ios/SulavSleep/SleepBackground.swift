import SwiftUI
import CoreMotion

// MARK: - Rainy Pixel Night background
//
// A living scene: a warm apartment window on a rainy evening. Six independent
// parallax layers, each drifting at its own speed, driven by the gyroscope
// (with a drag fallback on devices/simulators without motion). Everything keeps
// moving even when the phone is perfectly still. Movement is slow and subtle by
// design — it should read as weather, not software. See DESIGN.md.

struct SleepBackground: View {
    /// Whether to render the crescent moon (hidden during onboarding, kept for
    /// API compatibility with earlier call sites).
    var showsMoon = true

    @State private var parallax = ParallaxController()
    @State private var drag: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let p = parallax.isActive ? parallax.offset : drag

                ZStack {
                    SkyLayer(t: t, size: size, showsMoon: showsMoon)
                        .offset(x: p.width * 2, y: p.height * 2)
                    CityLayer(t: t, size: size)
                        .offset(x: p.width * 5, y: p.height * 3)
                    StreetGlowLayer(t: t, size: size)
                        .offset(x: p.width * 10, y: p.height * 6)
                    RainLayer(t: t, size: size)
                        .offset(x: p.width * 8, y: p.height * 4)
                    AtmosphereLayer(t: t, size: size)
                        .offset(x: p.width * 6, y: p.height * 4)
                    WindowLayer(t: t, size: size)
                        .offset(x: p.width * 14, y: p.height * 8)
                }
                // Overscan so a few pixels of parallax never reveal an edge.
                .scaleEffect(1.12)
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
                withAnimation(.interpolatingSpring(stiffness: 60, damping: 12)) {
                    drag = CGSize(width: max(-1, min(1, nx)), height: max(-1, min(1, ny)))
                }
            }
            .onEnded { _ in
                withAnimation(.interpolatingSpring(stiffness: 40, damping: 10)) {
                    drag = .zero
                }
            }
    }
}

// MARK: - Parallax controller (gyroscope, spring-smoothed)

@Observable
final class ParallaxController {
    /// Smoothed, normalized offset in roughly [-1, 1] on each axis.
    private(set) var offset: CGSize = .zero
    private(set) var isActive = false

    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        isActive = true
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let attitude = data?.attitude else { return }
            // Roll ≈ left/right tilt, pitch ≈ up/down. Neutral holding pitch ~0.5 rad.
            let targetX = max(-1, min(1, attitude.roll / 0.6))
            let targetY = max(-1, min(1, (attitude.pitch - 0.5) / 0.6))
            // Low-pass filter → spring-like easing, no snapping.
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

// MARK: - Layer 1: Sky (gradient, stars, drifting clouds, moon)

private struct SkyLayer: View {
    let t: TimeInterval
    let size: CGSize
    let showsMoon: Bool

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [SleepColor.skyTop, SleepColor.skyMid, SleepColor.skyBottom]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            for i in 0..<52 {
                let x = hash01(i, 1) * size.width
                let y = hash01(i, 2) * size.height * 0.68
                let base = 0.9 + hash01(i, 3) * 1.4
                let twinkle = 0.55 + 0.45 * sin(t * (0.6 + hash01(i, 4)) + Double(i))
                let alpha = (0.25 + hash01(i, 5) * 0.5) * twinkle
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: base, height: base)),
                    with: .color(.white.opacity(alpha))
                )
            }

            if showsMoon { drawMoon(&context, size: size) }
            drawClouds(&context, size: size)
        }
    }

    private func drawMoon(_ context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.76, y: size.height * 0.16)
        // Soft halo.
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 70, y: center.y - 70, width: 140, height: 140)),
            with: .radialGradient(
                Gradient(colors: [SleepColor.moon.opacity(0.10), .clear]),
                center: center, startRadius: 6, endRadius: 78
            )
        )
        // Disc.
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68)),
            with: .radialGradient(
                Gradient(colors: [.white, SleepColor.moon]),
                center: CGPoint(x: center.x - 8, y: center.y - 8), startRadius: 2, endRadius: 46
            )
        )
        // Crescent shadow.
        context.blendMode = .destinationOut
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 16, y: center.y - 42, width: 62, height: 62)),
            with: .color(.black)
        )
        context.blendMode = .normal
    }

    private func drawClouds(_ context: inout GraphicsContext, size: CGSize) {
        let drift = CGFloat(sin(t / 22) * 16)
        cloud(&context, CGPoint(x: size.width * 0.16 + drift, y: size.height * 0.24), 1.1, 0.05)
        cloud(&context, CGPoint(x: size.width * 0.62 - drift * 0.7, y: size.height * 0.15), 0.8, 0.04)
    }

    private func cloud(_ context: inout GraphicsContext, _ origin: CGPoint, _ scale: CGFloat, _ opacity: Double) {
        var path = Path()
        path.addEllipse(in: CGRect(x: origin.x, y: origin.y, width: 90 * scale, height: 30 * scale))
        path.addEllipse(in: CGRect(x: origin.x + 34 * scale, y: origin.y - 14 * scale, width: 70 * scale, height: 40 * scale))
        path.addEllipse(in: CGRect(x: origin.x + 60 * scale, y: origin.y, width: 84 * scale, height: 30 * scale))
        context.fill(path, with: .color(.white.opacity(opacity)))
    }
}

// MARK: - Layer 2: Distant pixel city

private struct CityLayer: View {
    let t: TimeInterval
    let size: CGSize

    var body: some View {
        Canvas { context, size in
            let horizon = size.height * 0.74
            let count = 22
            let unit = size.width / CGFloat(count)

            for b in 0..<count {
                let h = (0.10 + hash01(b, 11) * 0.20) * size.height
                let x = CGFloat(b) * unit
                let w = unit * (0.72 + hash01(b, 12) * 0.24)
                let rect = CGRect(x: x, y: horizon - h, width: w, height: h + 40)
                let shade = 0.10 + hash01(b, 13) * 0.05
                context.fill(Path(rect), with: .color(Color(hex: 0x0E1826, opacity: 0.9 + shade)))

                // Tiny warm windows, a few of which flicker on/off.
                let cols = max(1, Int(w / 7))
                let rows = max(1, Int(h / 9))
                for r in 0..<rows {
                    for c in 0..<cols {
                        let seed = b * 97 + r * 13 + c
                        guard hash01(seed, 21) > 0.62 else { continue }
                        let flick = sin(t * (0.15 + hash01(seed, 22) * 0.4) + Double(seed))
                        let lit = flick > (0.2 + hash01(seed, 23) * 0.5)
                        guard lit else { continue }
                        let wx = x + 3 + CGFloat(c) * 7
                        let wy = horizon - h + 4 + CGFloat(r) * 9
                        guard wx < x + w - 3, wy < horizon - 3 else { continue }
                        let warm = hash01(seed, 24) > 0.35
                        let color = warm ? SleepColor.windowGlow : SleepColor.rain
                        context.fill(
                            Path(CGRect(x: wx, y: wy, width: 2.2, height: 2.6)),
                            with: .color(color.opacity(0.35 + 0.35 * max(0, flick)))
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Layer 3: Street-light glow (soft orange bloom, slow pulse)

private struct StreetGlowLayer: View {
    let t: TimeInterval
    let size: CGSize

    var body: some View {
        Canvas { context, size in
            let glows: [(CGFloat, CGFloat, CGFloat, Double)] = [
                (0.18, 0.80, 150, 8),
                (0.52, 0.86, 200, 12),
                (0.84, 0.78, 170, 15),
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
                        Gradient(colors: [SleepColor.streetGlow.opacity(0.16 * pulse), .clear]),
                        center: center, startRadius: 0, endRadius: radius
                    )
                )
            }
        }
        .blendMode(.plusLighter)
    }
}

// MARK: - Layer 4: Rain (three depths)

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
            // Some near drops fade out halfway.
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
                // A brighter drop passing close to the camera.
                context.stroke(
                    line,
                    with: .color(.white.opacity(0.18)),
                    style: StrokeStyle(lineWidth: width * 2.4, lineCap: .round)
                )
            }
        }
    }
}

// MARK: - Layer 5: Foreground window (frame, condensation, sliding droplets, reflection)

private struct WindowLayer: View {
    let t: TimeInterval
    let size: CGSize

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 10
            let frame = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
            let shape = Path(roundedRect: frame, cornerRadius: 26)

            // Subtle inner vignette — the edge of the glass catching indoor light.
            context.stroke(shape, with: .color(SleepColor.streetGlow.opacity(0.05)), lineWidth: 2)
            context.stroke(
                Path(roundedRect: frame.insetBy(dx: 1, dy: 1), cornerRadius: 25),
                with: .color(.black.opacity(0.18)),
                lineWidth: 8
            )

            // Diagonal reflection streak, very faint.
            var streak = Path()
            streak.move(to: CGPoint(x: size.width * 0.12, y: 0))
            streak.addLine(to: CGPoint(x: size.width * 0.30, y: 0))
            streak.addLine(to: CGPoint(x: size.width * 0.08, y: size.height))
            streak.addLine(to: CGPoint(x: -size.width * 0.05, y: size.height))
            streak.closeSubpath()
            context.fill(streak, with: .color(.white.opacity(0.015)))

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

            // A few droplets sliding down the glass, each leaving a faint trail.
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

// MARK: - Layer 6: Floating atmosphere (faint drifting dust)

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
