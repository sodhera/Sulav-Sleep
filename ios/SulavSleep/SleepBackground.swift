import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Pixel city background (layered Core Animation)
//
// The background keeps every depth plane separate: each city layer scrolls and
// parallaxes independently. The scene stays calm and lets the pixel city carry
// the mood without extra foreground effects.
//
// The city follows the user's day: Day (hazy daylight, sun, windows off),
// Dusk (golden hour, windows coming on), Night (the original art). Variants
// are generated from the night layers by scripts/generate-scene-variants.py;
// the view crossfades between them at the phase boundaries.

/// Which lighting the city scene (and Home's sloth) wears. Bands match the
/// greeting copy: 5–17 day, 17–22 dusk, 22–5 night.
enum CityPhase: String {
    case day = "Day"
    case dusk = "Dusk"
    case night = "Night"

    static func current(_ date: Date = Date()) -> CityPhase {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<17: return .day
        case 17..<22: return .dusk
        default: return .night
        }
    }
}

struct SleepBackground: View {
    /// Kept for call-site compatibility; the sky asset includes the moon.
    var showsMoon = true
    /// When false (e.g. an off-screen tab) Core Animation pauses all motion.
    var isActive = true

    var body: some View {
        #if canImport(UIKit)
        PixelNightLayeredView(isActive: isActive)
            .ignoresSafeArea()
        #else
        SleepColor.background.ignoresSafeArea()
        #endif
    }
}

/// A soft readability veil laid over the city scene, beneath UI content. The
/// scene's lit windows and bright day sky can swallow light text; this
/// supplies the dark stage the ink system was designed for, per phase. It is full-bleed with
/// no edges or corners, so it reads as atmospheric haze rather than a card, and
/// never intercepts touches. Layer it directly above `SleepBackground`.
struct SceneReadabilityScrim: View {
    var body: some View {
        // The veil is phase-aware: the whole ink system (grey muted text,
        // white-opacity quiet/faint, gold heroes) was designed against a
        // dark night stage, so the brighter day and dusk scenes must supply
        // that stage themselves — a full-height veil, deepest where text
        // bands live. Night keeps its clear upper sky and moon.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let stops: [Gradient.Stop] = switch CityPhase.current(timeline.date) {
            case .day: [
                .init(color: SleepColor.background.opacity(0.38), location: 0.0),
                .init(color: SleepColor.background.opacity(0.30), location: 0.30),
                .init(color: SleepColor.background.opacity(0.55), location: 0.58),
                .init(color: SleepColor.background.opacity(0.82), location: 1.0),
            ]
            case .dusk: [
                .init(color: SleepColor.background.opacity(0.28), location: 0.0),
                .init(color: SleepColor.background.opacity(0.18), location: 0.30),
                .init(color: SleepColor.background.opacity(0.50), location: 0.58),
                .init(color: SleepColor.background.opacity(0.80), location: 1.0),
            ]
            case .night: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.30),
                .init(color: SleepColor.background.opacity(0.42), location: 0.58),
                .init(color: SleepColor.background.opacity(0.80), location: 1.0),
            ]
            }
            LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#if canImport(UIKit)
private struct PixelNightLayeredView: UIViewRepresentable {
    var isActive: Bool

    func makeUIView(context: Context) -> PixelNightUIView {
        PixelNightUIView()
    }

    func updateUIView(_ uiView: PixelNightUIView, context: Context) {
        uiView.setActive(isActive)
    }
}

private final class PixelNightUIView: UIView {
    private let citySpecs: [CityLayerSpec] = [
        .init(assetName: "CitySky", speed: 2.0, depth: 0.18),
        .init(assetName: "CityFarSkyline", speed: 3.8, depth: 0.30),
        .init(assetName: "CityMidSkyline", speed: 6.5, depth: 0.50),
        .init(assetName: "CityNearSkyline", speed: 10.5, depth: 0.74),
        .init(assetName: "CityFrontSkyline", speed: 15.0, depth: 1.00),
    ]

    private var cityViews: [ScrollingCityLayerView] = []
    private let glowOverlay = GlowOverlayView()
    private let warmOverlay = UIView()
    private let scrimLayer = CAGradientLayer()
    private var active = true
    private var phase = CityPhase.current()
    private var phaseTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The scene is purely ambient: it never reacts to touch, so it can't
        // intercept taps meant for the UI above it. Depth still comes from the
        // device-tilt motion effect, not gestures.
        isUserInteractionEnabled = false
        setupCityLayers()
        setupOverlays()
        applyPhase(animated: false)

        // The scene checks the clock once a minute and crossfades at the
        // phase boundaries. Tolerance keeps the timer power-friendly.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, CityPhase.current() != self.phase else { return }
            self.phase = CityPhase.current()
            self.applyPhase(animated: true)
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        phaseTimer = timer
    }

    deinit {
        phaseTimer?.invalidate()
    }

    private func applyPhase(animated: Bool) {
        cityViews.forEach { $0.apply(phase: phase, animated: animated) }
        let apply = {
            // Street glows and the warm wash belong to lit-window hours;
            // daylight gets a clear sky and carries its own light.
            self.glowOverlay.alpha = self.phase == .day ? 0 : 1
            self.warmOverlay.alpha = self.phase == .day ? 0 : 1
            self.backgroundColor = switch self.phase {
            case .day: UIColor(red: 0.55, green: 0.68, blue: 0.82, alpha: 1)
            case .dusk: UIColor(red: 0.16, green: 0.13, blue: 0.25, alpha: 1)
            case .night: UIColor(SleepColor.background)
            }
            // The scene's own scrim eases off in daylight so the sky can
            // actually read as day — the SwiftUI readability scrim above
            // still guards the text band.
            let scrimAlphas: [CGFloat] = self.phase == .day
                ? [0.42, 0.06, 0.62]
                : [0.60, 0.18, 0.78]
            self.scrimLayer.colors = scrimAlphas.map {
                UIColor(SleepColor.background).withAlphaComponent($0).cgColor
            }
        }
        if animated {
            UIView.animate(withDuration: 1.4, animations: apply)
        } else {
            apply()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cityViews.forEach { $0.frame = bounds }
        glowOverlay.frame = bounds
        warmOverlay.frame = bounds
        scrimLayer.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimationState()
    }

    func setActive(_ isActive: Bool) {
        active = isActive
        updateAnimationState()
    }

    private func setupCityLayers() {
        cityViews = citySpecs.map { ScrollingCityLayerView(spec: $0, phase: phase) }
        cityViews.forEach(addSubview)
    }

    private func setupOverlays() {
        glowOverlay.isUserInteractionEnabled = false
        addSubview(glowOverlay)

        warmOverlay.isUserInteractionEnabled = false
        warmOverlay.backgroundColor = UIColor(SleepColor.amber).withAlphaComponent(0.10)
        addSubview(warmOverlay)

        scrimLayer.colors = [
            UIColor(SleepColor.background).withAlphaComponent(0.60).cgColor,
            UIColor(SleepColor.background).withAlphaComponent(0.18).cgColor,
            UIColor(SleepColor.background).withAlphaComponent(0.78).cgColor,
        ]
        scrimLayer.locations = [0, 0.42, 1]
        layer.addSublayer(scrimLayer)
    }

    private func updateAnimationState() {
        setAnimationsPaused(window == nil || !active)
    }

    private func setAnimationsPaused(_ paused: Bool) {
        if paused, layer.speed != 0 {
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = pausedTime
        } else if !paused, layer.speed == 0 {
            let pausedTime = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        }
    }
}

private struct CityLayerSpec {
    let assetName: String
    let speed: CGFloat
    let depth: CGFloat

    var parallaxX: CGFloat { DepthMath.parallaxTravel(depth: depth, far: 2, near: 16) }
    var parallaxY: CGFloat { DepthMath.parallaxTravel(depth: depth, far: 1, near: 8) }
}

private final class ScrollingCityLayerView: UIView {
    private static let assetAspect: CGFloat = 16.0 / 9.0

    private let spec: CityLayerSpec
    private var phase: CityPhase
    private let motionHost = UIView()
    private let stripView = UIView()
    private var imageViews: [UIImageView] = []
    private var tileWidth: CGFloat = 0

    init(spec: CityLayerSpec, phase: CityPhase) {
        self.spec = spec
        self.phase = phase
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        configureTiles()
        configureMotionEffect()
    }

    /// Swap this plane's art to the given phase, crossfading in place. The
    /// scroll animation lives on the strip layer and is untouched, so the
    /// city never stutters while the light changes.
    func apply(phase: CityPhase, animated: Bool) {
        self.phase = phase
        guard let image = SleepAssetCache.image(named: phase.rawValue + spec.assetName) else {
            AppLog.scene.warning("Missing city layer asset: \(self.phase.rawValue + self.spec.assetName, privacy: .public)")
            return
        }
        for imageView in imageViews {
            if animated {
                UIView.transition(with: imageView, duration: 1.4, options: .transitionCrossDissolve) {
                    imageView.image = image
                }
            } else {
                imageView.image = image
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontalInset = -(spec.parallaxX + 28)
        let verticalInset = -(spec.parallaxY + 18)
        motionHost.frame = bounds.insetBy(dx: horizontalInset, dy: verticalInset)

        let nextTileWidth = max(motionHost.bounds.height * Self.assetAspect, motionHost.bounds.width)
        let tileHeight = motionHost.bounds.height
        stripView.frame = CGRect(
            x: (motionHost.bounds.width - nextTileWidth) / 2,
            y: 0,
            width: nextTileWidth * CGFloat(imageViews.count),
            height: tileHeight
        )

        for (index, imageView) in imageViews.enumerated() {
            imageView.frame = CGRect(
                x: CGFloat(index) * nextTileWidth,
                y: 0,
                width: nextTileWidth,
                height: tileHeight
            )
        }

        if abs(tileWidth - nextTileWidth) > 0.5 {
            tileWidth = nextTileWidth
            restartScrollAnimation()
        }
    }

    private func configureTiles() {
        guard let image = SleepAssetCache.image(named: phase.rawValue + spec.assetName) else {
            AppLog.scene.warning("Missing city layer asset: \(self.phase.rawValue + self.spec.assetName, privacy: .public)")
            return
        }

        for _ in 0..<3 {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleToFill
            imageView.layer.magnificationFilter = .nearest
            imageView.layer.minificationFilter = .nearest
            stripView.addSubview(imageView)
            imageViews.append(imageView)
        }

        motionHost.addSubview(stripView)
        addSubview(motionHost)
    }

    private func configureMotionEffect() {
        let horizontal = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
        horizontal.minimumRelativeValue = -spec.parallaxX
        horizontal.maximumRelativeValue = spec.parallaxX

        let vertical = UIInterpolatingMotionEffect(keyPath: "center.y", type: .tiltAlongVerticalAxis)
        vertical.minimumRelativeValue = -spec.parallaxY
        vertical.maximumRelativeValue = spec.parallaxY

        let group = UIMotionEffectGroup()
        group.motionEffects = [horizontal, vertical]
        motionHost.addMotionEffect(group)
    }

    private func restartScrollAnimation() {
        guard tileWidth > 0, spec.speed > 0 else { return }
        stripView.layer.removeAnimation(forKey: "city-scroll")

        let duration = CFTimeInterval(tileWidth / spec.speed)
        let localNow = stripView.layer.convertTime(CACurrentMediaTime(), from: nil)
        let phase = localNow.truncatingRemainder(dividingBy: duration)

        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -tileWidth
        animation.duration = duration
        animation.beginTime = localNow - phase
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        stripView.layer.add(animation, forKey: "city-scroll")
    }
}

private enum DepthMath {
    static func parallaxTravel(depth: CGFloat, far: CGFloat, near: CGFloat) -> CGFloat {
        far + (near - far) * pow(clamped(depth), 1.18)
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }
}

private final class GlowOverlayView: UIView {
    private let glowLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(glowLayer)
        addPulse()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glowLayer.frame = bounds
        glowLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        addGlow(x: 0.18, y: 0.80, radius: 150)
        addGlow(x: 0.52, y: 0.84, radius: 220)
        addGlow(x: 0.84, y: 0.78, radius: 170)
    }

    private func addGlow(x: CGFloat, y: CGFloat, radius: CGFloat) {
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [
            UIColor(SleepColor.streetGlow).withAlphaComponent(0.18).cgColor,
            UIColor(SleepColor.streetGlow).withAlphaComponent(0.02).cgColor,
            UIColor.clear.cgColor,
        ]
        glow.locations = [0, 0.52, 1]
        glow.frame = CGRect(
            x: bounds.width * x - radius,
            y: bounds.height * y - radius,
            width: radius * 2,
            height: radius * 2
        )
        glowLayer.addSublayer(glow)
    }

    private func addPulse() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.72
        animation.toValue = 1.0
        animation.duration = 5.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.add(animation, forKey: "glow-pulse")
    }
}
#endif
