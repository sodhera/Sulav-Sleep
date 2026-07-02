import AVFoundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Rainy Pixel Night background (video-backed)
//
// The rainy night scene is pre-rendered into RainyNightLoop.mp4 and played with
// AVPlayerLayer. That moves the continuous rain/glow work to the hardware video
// decoder instead of running an in-process SpriteKit or SwiftUI render loop.
// System motion effects provide a small parallax offset without app-side gyro
// polling. Regenerate the video with scripts/render-rainy-night-video.sh.

struct SleepBackground: View {
    /// Kept for call-site compatibility; the loop already includes the moon.
    var showsMoon = true
    /// When false (e.g. an off-screen tab) video playback pauses entirely.
    var isActive = true

    var body: some View {
        #if canImport(UIKit)
        RainyNightVideoPlayer(isActive: isActive)
            .ignoresSafeArea()
        #else
        SleepColor.background.ignoresSafeArea()
        #endif
    }
}

#if canImport(UIKit)
private struct RainyNightVideoPlayer: UIViewRepresentable {
    var isActive: Bool

    func makeUIView(context: Context) -> RainyNightVideoView {
        RainyNightVideoView()
    }

    func updateUIView(_ uiView: RainyNightVideoView, context: Context) {
        uiView.setActive(isActive)
    }
}

private final class RainyNightVideoView: UIView {
    private enum Layout {
        static let parallaxInsetX: CGFloat = -28
        static let parallaxInsetY: CGFloat = -36
        static let horizontalTravel: CGFloat = 10
        static let verticalTravel: CGFloat = 7
    }

    private let motionHost = UIView()
    private let fallbackImageView = UIImageView()
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var active = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(SleepColor.background)
        configureFallback()
        configureVideo()
        configureMotionEffects()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        motionHost.frame = bounds.insetBy(
            dx: Layout.parallaxInsetX,
            dy: Layout.parallaxInsetY
        )
        fallbackImageView.frame = motionHost.bounds
        playerLayer.frame = motionHost.bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    func setActive(_ isActive: Bool) {
        active = isActive
        updatePlayback()
    }

    private func configureFallback() {
        fallbackImageView.image = SleepAssetCache.image(named: "NightCity")
        fallbackImageView.contentMode = .scaleAspectFill
        fallbackImageView.clipsToBounds = true

        motionHost.clipsToBounds = false
        motionHost.addSubview(fallbackImageView)
        addSubview(motionHost)
    }

    private func configureVideo() {
        guard let url = Bundle.main.url(forResource: "RainyNightLoop", withExtension: "mp4") else {
            AppLog.scene.warning("RainyNightLoop.mp4 missing; using static background fallback")
            return
        }

        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.actionAtItemEnd = .none
        queue.preventsDisplaySleepDuringVideoPlayback = false

        playerLayer.player = queue
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.isOpaque = false
        playerLayer.backgroundColor = UIColor.clear.cgColor
        motionHost.layer.addSublayer(playerLayer)

        player = queue
        looper = AVPlayerLooper(player: queue, templateItem: item)
    }

    private func configureMotionEffects() {
        let horizontal = UIInterpolatingMotionEffect(
            keyPath: "center.x",
            type: .tiltAlongHorizontalAxis
        )
        horizontal.minimumRelativeValue = -Layout.horizontalTravel
        horizontal.maximumRelativeValue = Layout.horizontalTravel

        let vertical = UIInterpolatingMotionEffect(
            keyPath: "center.y",
            type: .tiltAlongVerticalAxis
        )
        vertical.minimumRelativeValue = -Layout.verticalTravel
        vertical.maximumRelativeValue = Layout.verticalTravel

        let group = UIMotionEffectGroup()
        group.motionEffects = [horizontal, vertical]
        motionHost.addMotionEffect(group)
    }

    private func updatePlayback() {
        guard window != nil, active else {
            player?.pause()
            return
        }
        player?.play()
    }
}
#endif
