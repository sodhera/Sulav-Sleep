import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Pixel Night background (layered Core Animation)
//
// The background keeps every depth plane separate: each city layer scrolls and
// parallaxes independently. The scene stays calm and lets the pixel city carry
// the mood without extra foreground effects.

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
        .init(assetName: "NightCitySky", speed: 2.0, depth: 0.18),
        .init(assetName: "NightCityFarSkyline", speed: 3.8, depth: 0.30),
        .init(assetName: "NightCityMidSkyline", speed: 6.5, depth: 0.50),
        .init(assetName: "NightCityNearSkyline", speed: 10.5, depth: 0.74),
        .init(assetName: "NightCityFrontSkyline", speed: 15.0, depth: 1.00),
    ]

    private var cityViews: [ScrollingCityLayerView] = []
    private let glowOverlay = GlowOverlayView()
    private let warmOverlay = UIView()
    private let scrimLayer = CAGradientLayer()
    private var active = true
    private var manualParallax = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = UIColor(SleepColor.background)
        setupCityLayers()
        setupOverlays()
        setupDragParallax()
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
        cityViews = citySpecs.map { ScrollingCityLayerView(spec: $0) }
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

    private func setupDragParallax() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            let translation = recognizer.translation(in: self)
            let x = min(1, max(-1, translation.x / 140))
            let y = min(1, max(-1, translation.y / 180))
            applyManualParallax(CGPoint(x: x, y: y), animated: false)
        case .ended, .cancelled, .failed:
            applyManualParallax(.zero, animated: true)
        default:
            break
        }
    }

    private func applyManualParallax(_ value: CGPoint, animated: Bool) {
        manualParallax = value
        let updates = {
            self.cityViews.forEach { $0.setManualParallax(value) }
        }

        if animated {
            UIView.animate(
                withDuration: 0.38,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: updates
            )
        } else {
            updates()
        }
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
    private let motionHost = UIView()
    private let stripView = UIView()
    private var imageViews: [UIImageView] = []
    private var tileWidth: CGFloat = 0

    init(spec: CityLayerSpec) {
        self.spec = spec
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        configureTiles()
        configureMotionEffect()
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
        guard let image = SleepAssetCache.image(named: spec.assetName) else {
            AppLog.scene.warning("Missing city layer asset: \(self.spec.assetName, privacy: .public)")
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

        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -tileWidth
        animation.duration = CFTimeInterval(tileWidth / spec.speed)
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        stripView.layer.add(animation, forKey: "city-scroll")
    }

    func setManualParallax(_ value: CGPoint) {
        motionHost.transform = CGAffineTransform(
            translationX: value.x * spec.parallaxX,
            y: value.y * spec.parallaxY
        )
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
