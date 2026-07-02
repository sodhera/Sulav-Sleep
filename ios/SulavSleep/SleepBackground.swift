import SwiftUI
import SpriteKit
import CoreMotion

// MARK: - Rainy Pixel Night background (SpriteKit)
//
// The animated background runs entirely on SpriteKit's Metal-backed renderer,
// completely outside SwiftUI's layout/diffing pipeline. Scrolling city layers
// and pulsing glow run at 30fps with zero SwiftUI overhead. Gyroscope parallax
// is polled in the update loop (no main-thread callbacks). The only SwiftUI
// bridge is a single SpriteView.
//
// The pixel art is the CraftPix night city (OGA-BY 3.0 — see CREDITS.md).
// See DESIGN.md for the full scene description.

// MARK: - SwiftUI wrapper

struct SleepBackground: View {
    /// Kept for call-site compatibility; the pixel scene includes its own moon.
    var showsMoon = true
    /// When false (e.g. an off-screen tab) the SpriteKit scene pauses entirely.
    var isActive = true

    @State private var scene: RainyNightScene = {
        let s = RainyNightScene(size: UIScreen.main.bounds.size)
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
            .onChange(of: isActive) { _, active in
                scene.isPaused = !active
            }
    }
}

// MARK: - SpriteKit scene

final class RainyNightScene: SKScene {

    // MARK: Layer configuration

    private struct LayerSpec {
        let assetName: String
        let speed: CGFloat   // px/sec scrolling left
        let xDepth: CGFloat  // gyroscope parallax multiplier
        let yDepth: CGFloat
    }

    private let layerSpecs: [LayerSpec] = [
        .init(assetName: "NightCitySky",          speed: 3,  xDepth: 2,  yDepth: 2),
        .init(assetName: "NightCityFarSkyline",   speed: 5,  xDepth: 4,  yDepth: 3),
        .init(assetName: "NightCityMidSkyline",   speed: 8,  xDepth: 7,  yDepth: 4),
        .init(assetName: "NightCityNearSkyline",  speed: 12, xDepth: 10, yDepth: 5),
        .init(assetName: "NightCityFrontSkyline", speed: 17, xDepth: 14, yDepth: 6),
    ]

    // MARK: Runtime state

    private struct ScrollingLayer {
        let container: SKNode
        let tiles: [SKSpriteNode]
        let spec: LayerSpec
    }

    private var scrollingLayers: [ScrollingLayer] = []
    private var lastUpdateTime: TimeInterval = 0

    // Parallax (gyroscope, polled in update — zero callbacks to main thread)
    private let motion = CMMotionManager()
    private var parallax = CGPoint.zero

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        // 30fps is plenty for slowly scrolling pixel art + rain.
        // Halves GPU load vs 60fps, reducing thermal throttling
        // that makes the keyboard and other UI feel sluggish.
        view.preferredFramesPerSecond = 30
        backgroundColor = UIColor(SleepColor.background)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        buildScene()
        startGyroscope()
    }

    override func willMove(from view: SKView) {
        stopGyroscope()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, size.height > 0, !scrollingLayers.isEmpty else { return }
        removeAllChildren()
        removeAllActions()
        scrollingLayers.removeAll()
        buildScene()
    }

    // MARK: Build scene

    private func buildScene() {
        setupCityLayers()
        setupWarmOverlay()
        setupNightScrim()
        setupGlow()
    }

    // MARK: Update loop (SpriteKit render thread — no SwiftUI involvement)

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : min(currentTime - lastUpdateTime, 0.1)
        lastUpdateTime = currentTime
        guard dt > 0 else { return }

        pollGyroscope(dt: dt)
        scrollLayers(dt: dt)
    }

    // MARK: - City layers

    private static let assetAspect: CGFloat = 16.0 / 9.0

    private func setupCityLayers() {
        for spec in layerSpecs {
            let container = SKNode()
            addChild(container)

            let tileW = max(size.height * Self.assetAspect, 1)
            let texture = SKTexture(imageNamed: spec.assetName)
            texture.filteringMode = .nearest  // Pixel art — no interpolation

            var tiles: [SKSpriteNode] = []
            for i in 0..<3 {
                let tile = SKSpriteNode(texture: texture,
                                        size: CGSize(width: tileW, height: size.height))
                tile.anchorPoint = CGPoint(x: 0, y: 0.5)
                // Position: tile 0 left of center, tile 1 at center, tile 2 right
                tile.position = CGPoint(x: CGFloat(i - 1) * tileW, y: 0)
                // Warm-desaturate the pixel art (replaces .saturation(0.55) + amber tint)
                tile.colorBlendFactor = 0.25
                tile.color = UIColor(SleepColor.navy)
                container.addChild(tile)
                tiles.append(tile)
            }

            scrollingLayers.append(ScrollingLayer(container: container,
                                                   tiles: tiles, spec: spec))
        }
    }

    private func scrollLayers(dt: TimeInterval) {
        let halfW = size.width / 2

        for layer in scrollingLayers {
            // Per-layer parallax on the container (free in SpriteKit — just a float)
            layer.container.position = CGPoint(
                x: parallax.x * layer.spec.xDepth,
                y: parallax.y * layer.spec.yDepth
            )

            // Scroll tiles left
            let tileW = layer.tiles[0].size.width
            for tile in layer.tiles {
                tile.position.x -= layer.spec.speed * CGFloat(dt)

                // Wrap: when tile's right edge passes the left screen edge (with buffer)
                if tile.position.x + tileW < -halfW - 40 {
                    tile.position.x += tileW * CGFloat(layer.tiles.count)
                }
            }
        }
    }

    // MARK: - Warm overlay (amber top → clear → ember bottom)

    private func setupWarmOverlay() {
        let tex = makeVerticalGradient(size: size, stops: [
            (UIColor(SleepColor.amber).withAlphaComponent(0.18), 0),
            (.clear, 0.5),
            (UIColor(SleepColor.crimsonGlow).withAlphaComponent(0.12), 1),
        ])
        let overlay = SKSpriteNode(texture: tex, size: size)
        overlay.blendMode = .add
        overlay.zPosition = 10
        addChild(overlay)
    }

    // MARK: - Night scrim (dark gradient for text legibility)

    private func setupNightScrim() {
        let bg = UIColor(SleepColor.background)
        let tex = makeVerticalGradient(size: size, stops: [
            (bg.withAlphaComponent(0.55), 0),
            (bg.withAlphaComponent(0.18), 0.42),
            (bg.withAlphaComponent(0.66), 1),
        ])
        let scrim = SKSpriteNode(texture: tex, size: size)
        scrim.blendMode = .alpha
        scrim.zPosition = 11
        addChild(scrim)
    }

    // MARK: - Street glow (pulsing amber circles)

    private func setupGlow() {
        let configs: [(x: CGFloat, y: CGFloat, r: CGFloat, period: TimeInterval)] = [
            (0.18, 0.18, 150, 8),   // relX/relY from center (0.5 = center)
            (0.52, 0.12, 200, 12),
            (0.84, 0.20, 170, 15),
        ]

        let glowTex = makeGlowTexture(radius: 128)

        for g in configs {
            let d = g.r * 2
            let node = SKSpriteNode(texture: glowTex, size: CGSize(width: d, height: d))
            node.position = CGPoint(
                x: (g.x - 0.5) * size.width,
                y: (g.y - 0.5) * size.height
            )
            node.color = UIColor(SleepColor.streetGlow)
            node.colorBlendFactor = 1
            node.alpha = 0.14
            node.blendMode = .add
            node.zPosition = 12

            // GPU-driven pulse via SKAction
            let pulse = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.20, duration: g.period / 2),
                SKAction.fadeAlpha(to: 0.10, duration: g.period / 2),
            ])
            node.run(.repeatForever(pulse))
            addChild(node)
        }
    }

    // MARK: - Gyroscope (polled — no callbacks, no main thread work)

    private func startGyroscope() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        // No handler — we poll in update(). Zero main-thread callbacks.
        motion.startDeviceMotionUpdates()
    }

    private func stopGyroscope() {
        guard motion.isDeviceMotionActive else { return }
        motion.stopDeviceMotionUpdates()
    }

    private func pollGyroscope(dt: TimeInterval) {
        guard let data = motion.deviceMotion else { return }
        let targetX = max(-1, min(1, CGFloat(data.attitude.roll / 0.6)))
        let targetY = max(-1, min(1, CGFloat((data.attitude.pitch - 0.5) / 0.6)))
        let k: CGFloat = 0.12
        parallax.x += (targetX - parallax.x) * k
        parallax.y += (targetY - parallax.y) * k
    }

    // MARK: - Texture generation (called once during setup)

    /// Soft radial gradient for glow circles (white — tinted via node.color).
    private func makeGlowTexture(radius: CGFloat) -> SKTexture {
        let d = radius * 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: d, height: d))
        let image = renderer.image { ctx in
            let gc = ctx.cgContext
            let center = CGPoint(x: radius, y: radius)
            let colors = [UIColor.white.cgColor, UIColor.clear.cgColor]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray, locations: [0, 1]
            ) else { return }
            gc.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: radius, options: [])
        }
        return SKTexture(image: image)
    }

    /// Top-to-bottom vertical gradient for overlays.
    private func makeVerticalGradient(size: CGSize,
                                       stops: [(color: UIColor, location: CGFloat)]) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let gc = ctx.cgContext
            let cgColors = stops.map { $0.color.cgColor }
            let locations = stops.map { $0.location }
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: cgColors as CFArray, locations: locations
            ) else { return }
            // UIGraphicsImageRenderer uses UIKit coords (y-down: 0=top)
            gc.drawLinearGradient(gradient, start: .zero,
                                  end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }
}
