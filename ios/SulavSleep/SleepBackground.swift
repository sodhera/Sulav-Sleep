import SwiftUI

struct SleepBackground: View {
    var showsMoon = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(rect),
                    with: .linearGradient(
                        Gradient(colors: [SleepColor.bgTop, SleepColor.bgMid, SleepColor.bgBottom]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                drawStars(in: &context, size: size, time: time)
                if showsMoon {
                    drawMoon(in: &context, size: size)
                }
                drawClouds(in: &context, size: size, time: time)
                drawMountains(in: &context, size: size)
            }
            .ignoresSafeArea()
        }
    }

    private func drawStars(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for index in 0..<42 {
            let x = CGFloat((index * 67) % 100) / 100 * size.width
            let y = CGFloat(((index * 37) % 56) + 2) / 100 * size.height * 0.72
            let radius = CGFloat(index % 4 == 0 ? 1.6 : 1.0) + CGFloat(index % 7 == 0 ? 1.0 : 0)
            let opacity = 0.36 + Double((index * 13) % 50) / 100
            let twinkle = 0.82 + 0.18 * sin(time * 1.2 + Double(index))
            let path = Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius))
            context.fill(path, with: .color(.white.opacity(opacity * twinkle)))
        }
    }

    private func drawMoon(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.78, y: size.height * 0.18)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 68, y: center.y - 68, width: 136, height: 136)),
            with: .color(.white.opacity(0.05))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84)),
            with: .linearGradient(
                Gradient(colors: [.white, SleepColor.moon]),
                startPoint: CGPoint(x: center.x - 30, y: center.y - 30),
                endPoint: CGPoint(x: center.x + 34, y: center.y + 34)
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 18, y: center.y - 52, width: 74, height: 74)),
            with: .linearGradient(
                Gradient(colors: [SleepColor.bgTop, SleepColor.bgMid]),
                startPoint: CGPoint(x: center.x, y: center.y - 56),
                endPoint: CGPoint(x: center.x, y: center.y + 20)
            )
        )
    }

    private func drawClouds(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let drift = CGFloat(sin(time / 8) * 14)
        drawCloud(in: &context, origin: CGPoint(x: size.width * 0.08 + drift, y: size.height * 0.25), scale: 1.05, opacity: 0.14)
        drawCloud(in: &context, origin: CGPoint(x: size.width * 0.58 - drift, y: size.height * 0.33), scale: 0.75, opacity: 0.12)
        drawCloud(in: &context, origin: CGPoint(x: size.width * 0.15 - drift * 0.7, y: size.height * 0.15), scale: 0.9, opacity: 0.08)
    }

    private func drawCloud(in context: inout GraphicsContext, origin: CGPoint, scale: CGFloat, opacity: Double) {
        var path = Path()
        path.move(to: CGPoint(x: origin.x + 12 * scale, y: origin.y + 38 * scale))
        path.addCurve(
            to: CGPoint(x: origin.x + 106 * scale, y: origin.y + 38 * scale),
            control1: CGPoint(x: origin.x + 12 * scale, y: origin.y + 12 * scale),
            control2: CGPoint(x: origin.x + 98 * scale, y: origin.y + 2 * scale)
        )
        path.addCurve(
            to: CGPoint(x: origin.x + 12 * scale, y: origin.y + 38 * scale),
            control1: CGPoint(x: origin.x + 122 * scale, y: origin.y + 54 * scale),
            control2: CGPoint(x: origin.x + 8 * scale, y: origin.y + 58 * scale)
        )
        context.fill(path, with: .color(.white.opacity(opacity)))
    }

    private func drawMountains(in context: inout GraphicsContext, size: CGSize) {
        context.fill(mountainPath(size: size, heightRatio: 0.30, baseline: 0.83), with: .color(Color(red: 36 / 255, green: 26 / 255, blue: 82 / 255)))
        context.fill(mountainPath(size: size, heightRatio: 0.22, baseline: 0.91), with: .color(Color(red: 22 / 255, green: 15 / 255, blue: 51 / 255)))
    }

    private func mountainPath(size: CGSize, heightRatio: CGFloat, baseline: CGFloat) -> Path {
        let height = size.height * heightRatio
        let top = size.height * baseline - height
        let base = size.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: base))
        path.addLine(to: CGPoint(x: 0, y: top + height * 0.55))
        path.addQuadCurve(to: CGPoint(x: size.width * 0.32, y: top + height * 0.5), control: CGPoint(x: size.width * 0.16, y: top + height * 0.18))
        path.addQuadCurve(to: CGPoint(x: size.width * 0.6, y: top + height * 0.42), control: CGPoint(x: size.width * 0.45, y: top + height * 0.74))
        path.addQuadCurve(to: CGPoint(x: size.width * 0.9, y: top + height * 0.46), control: CGPoint(x: size.width * 0.76, y: top + height * 0.08))
        path.addQuadCurve(to: CGPoint(x: size.width, y: top + height * 0.5), control: CGPoint(x: size.width * 0.97, y: top + height * 0.62))
        path.addLine(to: CGPoint(x: size.width, y: base))
        path.closeSubpath()
        return path
    }
}
