import SwiftUI
import AVKit

struct BedtimePhoneDial: View {
    @Binding var minutes: Int
    @Binding var touched: Bool

    var body: some View {
        VStack(spacing: 24) {
            GeometryReader { geo in
                let side = min(geo.size.width, 320.0)
                let center = CGPoint(x: geo.size.width / 2, y: side / 2)
                ZStack {
                    Circle().trim(from: 0.125, to: 0.875)
                        .stroke(SleepColor.ink.opacity(0.12), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(90))
                    Circle().trim(from: 0.125, to: 0.125 + 0.75 * Double(minutes) / 240)
                        .stroke(SleepColor.amber, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(90))
                    ForEach(0..<49) { tick in
                        Rectangle().fill(tick % 4 == 0 ? SleepColor.gold : SleepColor.dim.opacity(0.4))
                            .frame(width: 2, height: tick % 4 == 0 ? 12 : 5)
                            .offset(y: -side / 2 + 26)
                            .rotationEffect(.degrees(-135 + Double(tick) * 270 / 48))
                    }
                    Capsule().fill(SleepColor.gold)
                        .frame(width: 4, height: side * 0.22)
                        .offset(y: -side * 0.11)
                        .rotationEffect(.degrees(-135 + Double(minutes) / 240 * 270))
                    Circle().fill(SleepColor.gold).frame(width: 13, height: 13)
                    VStack(spacing: 2) {
                        Text(minutes == 240 ? "4+" : "\(minutes)")
                            .font(SleepFont.hero(48)).contentTransition(.numericText())
                        Text(minutes == 240 ? "hours" : "minutes").font(SleepFont.body(15))
                    }.foregroundStyle(SleepColor.ink).offset(y: side * 0.30)
                }
                .frame(width: side - 24, height: side - 24)
                .position(center)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let dx = value.location.x - center.x
                    let dy = value.location.y - center.y
                    var angle = atan2(dy, dx) * 180 / .pi - 135
                    if angle < 0 { angle += 360 }
                    let clamped = angle > 315 ? 0 : min(angle, 270)
                    let next = Int((clamped / 270 * 240 / 5).rounded()) * 5
                    if next != minutes { Haptics.soft() }
                    minutes = next
                    touched = true
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Phone time before bed")
                .accessibilityValue(minutes == 240 ? "4 or more hours" : "\(minutes) minutes")
                .accessibilityHint("Adjust to set your nightly phone time")
                .accessibilityAdjustableAction { direction in
                    touched = true
                    switch direction {
                    case .increment: minutes = min(240, minutes + 5)
                    case .decrement: minutes = max(0, minutes - 5)
                    @unknown default: break
                    }
                }
            }.frame(height: 320)
            HStack {
                Text("0 min")
                Spacer()
                Text("4+ hours")
            }.font(SleepFont.body(14)).foregroundStyle(SleepColor.dim)
            Text("Turn the dial")
                .font(SleepFont.body(15)).foregroundStyle(SleepColor.dim)
        }
    }
}

/// Text reveals are cancellable, pause off-screen, and read as complete sentences to VoiceOver.
struct NarrativePage: View {
    let lines: [String]
    var footnote: String? = nil
    @Binding var ready: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = 0

    private var count: Int { lines.reduce(0) { $0 + $1.count } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: lines.count > 3 ? 20 : 28) {
                ForEach(lines.indices, id: \.self) { index in
                    let preceding = lines.prefix(index).reduce(0) { $0 + $1.count }
                    let text = String(lines[index].prefix(max(0, visible - preceding)))
                    Text(text.isEmpty ? " " : text)
                        .font(SleepFont.title(lines.count > 3 ? 22 : 28))
                        .foregroundStyle(index == 0 ? SleepColor.ink : SleepColor.gold)
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(lines[index])
                }
                if ready, let footnote {
                    Text(footnote).font(SleepFont.body(12)).foregroundStyle(SleepColor.dim)
                }
            }.padding(.vertical, 36)
        }
        .scrollIndicators(.hidden)
        .task(id: lines) {
            visible = 0
            ready = false
            if reduceMotion || voiceOver { visible = count; ready = true; return }
            do {
                try await Task.sleep(for: .milliseconds(450))
                for index in 1...max(1, count) {
                    while scenePhase != .active { try await Task.sleep(for: .milliseconds(150)) }
                    try Task.checkCancellation()
                    visible = index
                    if index % 4 == 0 { Haptics.soft() }
                    let boundaries = lines.indices.map { lines.prefix($0 + 1).reduce(0) { $0 + $1.count } }
                    try await Task.sleep(for: .milliseconds(boundaries.contains(index) ? 650 : 38))
                }
                ready = true
            } catch { /* Navigation cancels the reveal. */ }
        }
    }
}

struct AttentionStoryStep: View {
    let minutes: Int
    let struggles: Set<SleepStruggle>
    @Binding var goal: SleepGoal?
    @State private var chapter = 0
    @State private var ready = false
    @Binding var showingOptions: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var consequences: [String] {
        var lines: [String] = []
        if struggles.contains(.fallingAsleep) { lines.append("The enemy keeps asking for your attention, even when you’re worried and trying to sleep.") }
        if struggles.contains(.wakingAtNight) { lines.append("When you wake in the middle of the night, it is waiting for your attention.") }
        if struggles.contains(.wakingTired) { lines.append("Even when you wake up tired, it wants you to come back.") }
        if struggles.contains(.negativeThoughts) { lines.append("It fills your attention with noise, leaving less room for the beauty around you.") }
        return lines.isEmpty ? ["Your attention belongs to you. Your nights can, too."] : lines
    }
    private var lines: [String] {
        switch chapter {
        case 0: ["There is an enemy living in your phone."]
        case 1: ["It is taking away \(minutes == 240 ? "at least " : "")\(minutes) minutes of your life each day.",
                 "That’s \(AttentionEstimate.yearlyMinutes(minutes).formatted()) minutes each year.",
                 "\(AttentionEstimate.lifetimeDays(minutes).formatted()) days in a life."]
        case 2: consequences
        default: ["What would make your night better?"]
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showingOptions {
                Text("What would make your night better?")
                    .font(SleepFont.title(28)).foregroundStyle(SleepColor.ink)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                Spacer(minLength: 10)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(SleepGoal.allCases) { option in
                            OptionRow(icon: option.systemImage, title: option.title, isSelected: goal == option) {
                                Haptics.soft(); goal = option
                            }
                        }
                    }.padding(.vertical, 3)
                }.scrollIndicators(.hidden)
                Spacer(minLength: 10)
            } else {
                NarrativePage(lines: lines,
                    footnote: chapter == 1 ? "An illustration at this daily rate for 365 days a year over 80 years, not a prediction of your life." : nil,
                    ready: $ready)
                    .id(chapter)
                    .transition(.opacity)
                if chapter < 3 {
                    StoryUnlockSlider {
                        ready = false
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { chapter += 1 }
                    }
                    .id(chapter)
                    .disabled(!ready).opacity(ready ? 1 : 0)
                    .padding(.bottom, 16)
                }
            }
        }
        .onChange(of: ready) { _, value in
            if value && chapter == 3 {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) { showingOptions = true }
            }
        }

    }
}

struct StoryUnlockSlider: View {
    let action: () -> Void
    @State private var offset: CGFloat = 0
    @State private var completed = false
    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - 66)
            ZStack(alignment: .leading) {
                Capsule().fill(SleepColor.navy.opacity(0.88))
                Capsule().stroke(SleepColor.amber.opacity(0.4), lineWidth: 1)
                Text("slide to unlock")
                    .font(SleepFont.body(18)).foregroundStyle(SleepColor.ink)
                    .frame(maxWidth: .infinity).opacity(1 - Double(offset / travel))
                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SleepColor.background)
                    .frame(width: 56, height: 50)
                    .background(SleepColor.gold, in: Capsule())
                    .offset(x: 5 + offset)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !completed else { return }
                            offset = min(travel, max(0, value.translation.width))
                        }
                        .onEnded { _ in
                            guard !completed else { return }
                            if offset >= travel * 0.85 {
                                completed = true; Haptics.success(); action()
                            } else { withAnimation(.spring()) { offset = 0 } }
                        })
            }
        }.frame(height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slide to unlock the next page")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { guard !completed else { return }; completed = true; action() }
    }
}

struct CommitmentHoldButton: View {
    let action: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var progress = 0.0
    @State private var task: Task<Void, Never>?
    @State private var complete = false
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SleepColor.navy)
                Capsule().fill(SleepColor.gold.opacity(0.8)).frame(width: geo.size.width * progress)
                Capsule().stroke(SleepColor.gold.opacity(0.5), lineWidth: 1)
                Label(complete ? "Committed" : "Hold to commit", systemImage: "hand.raised.fill")
                    .font(SleepFont.label(18))
                    .foregroundStyle(progress > 0.55 ? SleepColor.background : SleepColor.ink)
                    .frame(maxWidth: .infinity)
            }.contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if abs(value.translation.width) > 45 || abs(value.translation.height) > 45 { cancel(); return }
                    start()
                }.onEnded { _ in cancel() })
        }.frame(height: 60)
        .onDisappear { cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold to commit")
        .accessibilityHint("Hold for two seconds to commit to your nights")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Commit") { guard !complete else { return }; complete = true; action() }
    }
    private func start() {
        guard task == nil, !complete else { return }
        Haptics.soft()
        task = Task { @MainActor in
            do {
                for tick in 1...40 {
                    try await Task.sleep(for: .milliseconds(50))
                    progress = Double(tick) / 40
                    if tick % 10 == 0 { Haptics.soft() }
                }
                complete = true; Haptics.success(); action()
            } catch { }
        }
    }
    private func cancel() {
        task?.cancel(); task = nil
        if !complete { withAnimation(.easeOut(duration: 0.18)) { progress = 0 } }
    }
}

struct BlockingPreviewStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Protect your attention")
                .font(SleepFont.title(28)).foregroundStyle(SleepColor.ink)
            Text("The scroll can wait. Your life can’t.")
                .font(SleepFont.body(16)).foregroundStyle(SleepColor.dim)
            GeometryReader { geo in
                let height = min(geo.size.height, 490.0)
                BlockingDemoPlayback()
                    .frame(width: height * 0.47, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: height * 0.065))
                    .padding(5)
                    .background(.black, in: RoundedRectangle(cornerRadius: height * 0.075))
                    .overlay(RoundedRectangle(cornerRadius: height * 0.075).stroke(.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("Illustrative demo · Choose apps after setup")
                .font(SleepFont.body(12)).foregroundStyle(SleepColor.dim)
                .frame(maxWidth: .infinity)
        }.padding(.bottom, 18)
    }
}

/// An explicit recreation, never presented as proof of granted Screen Time permissions.
/// Fixed iPhone coordinates keep the status bar, app launch, and shield readable at card scale.
struct IPhoneBlockingDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var stage = 0
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(hex: 0x122843), Color(hex: 0x56798A), Color(hex: 0x121E37)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if stage < 2 { home }
                if stage == 2 {
                    Color.black
                    VStack(spacing: 24) { tiktokMark.font(.system(size: 90, weight: .bold)); Text("TikTok").font(.system(size: 34, weight: .bold)) }
                        .foregroundStyle(.white)
                }
                if stage == 3 { feed }
                if stage >= 4 { shield.transition(.opacity) }
                VStack {
                    HStack {
                        Text("9:41").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "cellularbars")
                        Image(systemName: "wifi")
                        Image(systemName: "battery.100percent")
                    }.font(.system(size: 13)).padding(.horizontal, 26).padding(.top, 18)
                    Spacer()
                    Capsule().fill(.white).frame(width: 130, height: 5).padding(.bottom, 9)
                }.foregroundStyle(.white)
                Capsule().fill(.black).frame(width: 115, height: 32).frame(maxHeight: .infinity, alignment: .top).padding(.top, 10)
            }
            .frame(width: 393, height: 852)
            .scaleEffect(geo.size.width / 393, anchor: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustrative iPhone demo: TikTok is tapped, opens, then SleepBlock displays the bedtime shield.")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if reduceMotion { stage = 4; return }
            do {
                while !Task.isCancelled {
                    stage = 0; try await Task.sleep(for: .milliseconds(1600))
                    stage = 1; try await Task.sleep(for: .milliseconds(450))
                    stage = 2; try await Task.sleep(for: .milliseconds(650))
                    stage = 3; try await Task.sleep(for: .milliseconds(600))
                    withAnimation(.easeOut(duration: 0.2)) { stage = 4 }
                    try await Task.sleep(for: .milliseconds(3200))
                }
            } catch { }
        }
    }
    private var tiktokMark: some View {
        Text("♪").foregroundStyle(.white)
            .shadow(color: .cyan, radius: 0, x: -3, y: -1)
            .shadow(color: .pink, radius: 0, x: 3, y: 2)
    }
    private var home: some View {
        VStack(spacing: 28) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("MONDAY").font(.system(size: 13, weight: .medium)).foregroundStyle(.red)
                    Text("17").font(.system(size: 48, weight: .light))
                    Text("A quieter night").font(.system(size: 13))
                }.foregroundStyle(.black).frame(width: 140, height: 135).background(.white.opacity(0.93), in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 25))
                    Text("18°").font(.system(size: 42, weight: .light))
                    Text("Clear tonight").font(.system(size: 13))
                }.foregroundStyle(.white).frame(width: 140, height: 135).background(Color(hex: 0x243E62), in: RoundedRectangle(cornerRadius: 22))
            }.padding(.top, 100)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 15), count: 4), spacing: 25) {
                appIcon("FaceTime", symbol: "video.fill", color: .green)
                appIcon("Photos", symbol: "camera.macro", color: .pink)
                appIcon("Camera", symbol: "camera.fill", color: .gray)
                appIcon("Mail", symbol: "envelope.fill", color: .blue)
                appIcon("Clock", symbol: "clock.fill", color: .black)
                appIcon("Maps", symbol: "map.fill", color: .green)
                appIcon("Notes", symbol: "note.text", color: .yellow)
                appIcon("Settings", symbol: "gear", color: .gray)
                VStack(spacing: 7) {
                    tiktokMark.font(.system(size: 43, weight: .bold))
                        .frame(width: 62, height: 62).background(.black, in: RoundedRectangle(cornerRadius: 15))
                        .scaleEffect(stage == 1 ? 0.88 : 1)
                        .overlay {
                            if stage == 1 { Circle().fill(.white.opacity(0.3)).frame(width: 42, height: 42).overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2)).offset(x: 10, y: 13) }
                        }
                    Text("TikTok").font(.system(size: 12)).foregroundStyle(.white)
                }
                appIcon("Podcasts", symbol: "mic.fill", color: .purple)
                appIcon("Books", symbol: "book.fill", color: .orange)
                appIcon("SleepBlock", symbol: "moon.zzz.fill", color: Color(hex: 0x172334))
            }
            Spacer()
            HStack(spacing: 6) { Circle().fill(.white); Circle().fill(.white.opacity(0.4)) }.frame(width: 18, height: 5)
            HStack(spacing: 24) {
                dockIcon("phone.fill", color: .green); dockIcon("safari", color: .blue)
                dockIcon("message.fill", color: .green); dockIcon("music.note", color: .pink)
            }.padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30)).padding(.bottom, 30)
        }
    }
    private func appIcon(_ name: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 7) { dockIcon(symbol, color: color); Text(name).font(.system(size: 12)).foregroundStyle(.white) }
    }
    private func dockIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 29)).foregroundStyle(.white)
            .frame(width: 62, height: 62).background(color.gradient, in: RoundedRectangle(cornerRadius: 15))
    }
    private var feed: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x163549), Color(hex: 0x9D715A), .black], startPoint: .top, endPoint: .bottom)
            Image("NightCityNearSkyline").resizable().scaledToFill().frame(width: 393, height: 852).clipped().opacity(0.8)
            VStack {
                Text("Following   For You").font(.system(size: 18, weight: .bold)).padding(.top, 90)
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("@nightcity").bold(); Text("One more video…"); Text("♫ original sound").font(.system(size: 13))
                    }
                    Spacer()
                    VStack(spacing: 26) { Image(systemName: "heart.fill"); Image(systemName: "bubble.right.fill"); Image(systemName: "arrowshape.turn.up.right.fill") }.font(.system(size: 27))
                }.padding(22)
                HStack(spacing: 45) { Image(systemName: "house.fill"); Image(systemName: "magnifyingglass"); Image(systemName: "plus.app"); Image(systemName: "tray"); Image(systemName: "person") }.padding(.bottom, 42)
            }.foregroundStyle(.white)
        }
    }
    private var shield: some View {
        ZStack {
            SleepColor.background
            VStack(spacing: 23) {
                Image("HomeSlothNightBlink").resizable().scaledToFit().frame(width: 160, height: 96)
                Text("SleepBlock").font(.system(size: 17, weight: .medium)).foregroundStyle(SleepColor.gold)
                Text("Your night is protected.").font(.system(size: 27, weight: .semibold)).multilineTextAlignment(.center)
                Text("TikTok can wait until morning.\nThis time belongs to you.")
                    .font(.system(size: 17)).foregroundStyle(SleepColor.dim).multilineTextAlignment(.center).lineSpacing(5)
                Text("Back to sleep").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SleepColor.background).frame(width: 280, height: 52).background(SleepColor.amber, in: Capsule()).padding(.top, 12)
                Text("I need a moment").font(.system(size: 14)).foregroundStyle(SleepColor.dim)
            }.foregroundStyle(SleepColor.ink).padding(28)
        }
    }
}

/// Bundled simulator recording, with a live illustration fallback and a static
/// shield for Reduce Motion. Player/looper ownership ends with the page.
private struct BlockingDemoPlayback: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if !reduceMotion, let url = Bundle.main.url(forResource: "attention-demo", withExtension: "mp4") {
                LoopingDemoMovie(url: url, playing: scenePhase == .active)
            } else {
                IPhoneBlockingDemo()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustrative iPhone demo: TikTok is tapped, opens, then SleepBlock displays the bedtime shield.")
    }
}

private struct LoopingDemoMovie: UIViewRepresentable {
    let url: URL
    let playing: Bool
    final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        init(url: URL) {
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIView(context: Context) -> DemoMovieSurface {
        let view = DemoMovieSurface()
        view.playerLayer.player = context.coordinator.player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: DemoMovieSurface, context: Context) {
        if playing { context.coordinator.player.play() } else { context.coordinator.player.pause() }
    }
    static func dismantleUIView(_ view: DemoMovieSurface, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.looper?.disableLooping()
        coordinator.player.removeAllItems()
    }
}

private final class DemoMovieSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
