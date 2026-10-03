import AudioToolbox
import DopagakiCore
import SwiftUI

@MainActor
public struct CompletionView: View {
    private let presentation: CompletionPresentation
    private let haptics: HapticLevel
    private let soundEnabled: Bool
    private let reduceMotion: Bool
    private let onClose: () -> Void
    private let onRecord: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var starFeedback = StarImpactFeedback()
    @StateObject private var rewardScene: RewardScene
    @State private var stage: RewardStage = .stars
    @State private var shownXP = 0
    @State private var displayedLevel: Int
    @State private var displayedLevelXP: Double
    @State private var started = false
    @State private var stopped = false
    @State private var particlesActive = true
    @State private var bursts: [RewardBurst] = []
    @State private var levelVisible = false
    @State private var mustClearVisible = false
    @State private var showingMedals = false
    @State private var rewardBeat = 0

    public init(presentation: CompletionPresentation, haptics: HapticLevel, soundEnabled: Bool, reduceMotion: Bool, onClose: @escaping () -> Void, onRecord: @escaping () -> Void) {
        self.presentation = presentation
        self.haptics = haptics
        self.soundEnabled = soundEnabled
        self.reduceMotion = reduceMotion
        self.onClose = onClose
        self.onRecord = onRecord
        _rewardScene = StateObject(wrappedValue: RewardScene(stars: presentation.stars))
        _displayedLevel = State(initialValue: presentation.previousXP / 250 + 1)
        _displayedLevelXP = State(initialValue: Double(presentation.previousXP % 250))
    }

    private var motionReduced: Bool { reduceMotion || systemReduceMotion }
    private var resultVisible: Bool { stage != .stars }

    public var body: some View {
        GeometryReader { geometry in
            let viewport = min(380.0, max(275.0, geometry.size.width * 0.92))
            ZStack {
                RewardBackdrop()
                if typeSize.isAccessibilitySize {
                    // Large accessibility text remains readable without shrinking it.
                    ScrollView {
                        completionContent(viewport: viewport, compact: true, scrolling: true)
                    }
                } else {
                    completionContent(viewport: viewport, compact: geometry.size.height < 700, scrolling: false)
                }
            }
            .overlay {
                RewardParticles(bursts: bursts, active: particlesActive && !motionReduced)
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.55),
                            .init(color: .white.opacity(0.18), location: 0.78),
                            .init(color: .clear, location: 0.92)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
        }
        .sheet(isPresented: $showingMedals) {
            NavigationStack {
                ScrollView { medals.padding(24) }
                    .navigationTitle("獲得したメダル")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("閉じる") { showingMedals = false }
                        }
                    }
                    .dopaPage()
            }
            .presentationDetents([.medium, .large])
        }
        .task { await playSequence() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { settleImmediately() }
        }
        .onChange(of: systemReduceMotion) { _, enabled in
            if enabled { settleImmediately() }
        }
        .onDisappear {
            stopped = true
            starFeedback.stop()
            rewardScene.stop()
            HapticsService.stop()
        }
    }

    private func completionContent(viewport: CGFloat, compact: Bool, scrolling: Bool) -> some View {
        let rewardLayout = scrolling ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
        return VStack(spacing: compact ? 6 : 10) {
            header
                .frame(minHeight: 44)
            Text(presentation.taskTitle)
                .font(.system(compact ? .subheadline : .headline, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(scrolling ? nil : 2)
                .truncationMode(.tail)
                .accessibilityLabel(presentation.taskTitle)

            rewardArtwork(viewport: viewport)
                .frame(minHeight: scrolling ? 180 : (compact ? 80 : 120),
                       maxHeight: scrolling ? 180 : .infinity)
                .layoutPriority(-1)

            VStack(spacing: compact ? 3 : 6) {
                Text(resultTitle)
                    .font(.system(compact ? .title2 : .title, design: .rounded, weight: .black))
                    .multilineTextAlignment(.center)
                    .lineLimit(scrolling ? nil : 2)
                    .minimumScaleFactor(0.8)
                rewardLayout {
                    if presentation.xp > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("+\(shownXP)")
                                .font(.system(size: compact ? 38 : 48, weight: .black, design: .rounded))
                                .contentTransition(.numericText(value: Double(shownXP)))
                                .monospacedDigit()
                                .lineLimit(1)
                            Text("XP").font(.system(.headline, design: .rounded, weight: .black))
                        }
                        .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.19))
                        .shadow(color: .orange.opacity(0.25), radius: 16)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("獲得経験値、\(shownXP) XP")
                    }
                    if presentation.stars > 0 {
                        Label("×\(presentation.stars)", systemImage: "star.fill")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("獲得した星、\(presentation.stars)個")
                    }
                }
            }
            .phaseAnimator([1.0, 1.12, 1.0], trigger: rewardBeat) { content, scale in
                content.scaleEffect(motionReduced ? 1 : scale)
            } animation: { scale in
                scale > 1 ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.55)
            }
            .opacity(resultVisible ? 1 : 0.32)

            levelProgress

            if !presentation.newMedals.isEmpty {
                medalSummary(compact: compact)
                    .opacity(resultVisible ? 1 : 0)
                    .disabled(!resultVisible)
                    .accessibilityHidden(!resultVisible)
            }

            actions
        }
        .padding(.horizontal, 24)
        .padding(.vertical, compact ? 4 : 8)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: scrolling ? nil : .infinity)
    }

    private func rewardArtwork(viewport: CGFloat) -> some View {
        GeometryReader { region in
            let artworkHeight = viewport - 60
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.yellow.opacity(0.18), .clear], center: .center, startRadius: 5, endRadius: viewport * 0.46))
                    .frame(width: viewport, height: viewport)
                RewardSceneView(rewardScene: rewardScene, isPlaying: stage != .settled)
                    .frame(height: viewport)
                    .accessibilityHidden(true)
                if levelVisible || mustClearVisible {
                    Text(mustClearVisible ? "ALL CLEAR!" : "LEVEL UP!")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(mustClearVisible ? DopaTheme.green : .white)
                        .shadow(color: (mustClearVisible ? DopaTheme.green : .cyan).opacity(0.65), radius: 12)
                        .rotationEffect(.degrees(mustClearVisible ? 0 : -7))
                        .offset(y: -viewport * 0.30)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            // Keep SceneKit's viewport stable, and scale the artwork into the
            // space remaining after the result, progress and buttons are laid out.
            .frame(width: region.size.width, height: artworkHeight)
            .scaleEffect(min(1, region.size.height / artworkHeight))
            .frame(width: region.size.width, height: region.size.height)
        }
        .clipped()
        .allowsHitTesting(false)
    }

    private func medalSummary(compact: Bool) -> some View {
        Button { showingMedals = true } label: {
            HStack(spacing: 8) {
                HStack(spacing: -8) {
                    ForEach(presentation.newMedals.prefix(3)) { medal in
                        MedalBadge(kind: medal.id, earned: true)
                            .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
                    }
                }
                Text("新しいメダル \(presentation.newMedals.count)個")
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold())
            }
            .foregroundStyle(.yellow)
            .padding(.horizontal, 12)
            .frame(minHeight: compact ? 44 : 52)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("メダル獲得、\(presentation.newMedals.map { $0.id.title }.joined(separator: "、"))。詳細を表示")
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.62, green: 0.98, blue: 0.64))
                Text(presentation.stars > 0 ? "TASK CLEAR" : "ACTIVITY SAVED")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(1.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 12)
            if stage != .settled {
                Button(action: settleImmediately) {
                    Text("スキップ")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("演出をスキップして結果を表示")
            }
        }
    }

    private var resultTitle: String {
        switch stage {
        case .stars: return presentation.stars > 0 ? "やりきった！" : "新しいメダル！"
        case .xp: return "やりきった！"
        case .level: return "レベル \(presentation.level) に！"
        case .medal: return "メダル獲得！"
        case .mustClear: return "今日のマスト全達成！"
        case .settled:
            if presentation.didCompleteTodaysMust { return "今日のマスト全達成！" }
            if presentation.didLevelUp { return "レベル \(presentation.level) に！" }
            return presentation.stars > 0 ? "やりきった！" : "メダル獲得！"
        }
    }

    private var levelProgress: some View {
        let level = displayedLevel
        let withinLevel = min(250, max(0, Int(displayedLevelXP.rounded(.down))))
        let headingLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
        return VStack(spacing: 7) {
            headingLayout {
                Label("LEVEL \(level)", systemImage: "bolt.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("\(withinLevel) / 250 XP")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 1, green: 0.59, blue: 0.05), Color(red: 1, green: 0.92, blue: 0.36)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * CGFloat(withinLevel) / 250)
                }
            }
            .frame(height: 10)
            .accessibilityLabel("レベル\(level)、次のレベルまで\(250 - withinLevel) XP")
            .accessibilityValue("\(withinLevel) / 250")
            Text(withinLevel == 250 ? "レベル \(level + 1) に到達！" : "あと\(250 - withinLevel) XPでレベル \(level + 1)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.yellow)
        }
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.1), lineWidth: 1))
    }

    private var medals: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEW MEDALS")
                .font(.system(.caption, design: .rounded, weight: .black))
                .tracking(2)
                .foregroundStyle(.yellow)
            ForEach(presentation.newMedals) { medal in
                HStack(spacing: 14) {
                    MedalBadge(kind: medal.id, earned: true)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(medal.id.title)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Text(medal.id.condition)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }
                .padding(14)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("メダル獲得、\(medal.id.title)。\(medal.id.condition)")
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 4) {
            Button {
                if stage == .settled {
                    HapticsService.tap(level: haptics)
                    onClose()
                } else {
                    settleImmediately()
                }
            } label: {
                Text(stage == .settled ? "つぎへ進む" : "結果をすぐ見る")
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(Color(red: 0.22, green: 0.17, blue: 0.01))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 49)
                    .modifier(DopaRewardSurface())
            }
            .buttonStyle(RewardPressStyle())
            .padding(.bottom, 5)
            Button {
                HapticsService.tap(level: haptics)
                onRecord()
            } label: {
                Label("話して記録する", systemImage: "mic.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .opacity(stage == .settled ? 1 : 0)
            .disabled(stage != .settled)
            .accessibilityHidden(stage != .settled)
        }
        .padding(.top, 2)
    }

    /// XP is already persisted by AppStore. This sequence only presents that receipt.
    private func playSequence() async {
        guard !started, !stopped else { return }
        started = true
        if motionReduced {
            settleImmediately()
            HapticsService.success(level: haptics)
            return
        }
        if presentation.stars > 0 {
            starFeedback.prepare(level: haptics, soundEnabled: soundEnabled)
        }
        defer { starFeedback.stop() }
        do {
            if presentation.stars == 0, let firstMedal = presentation.newMedals.first {
                stage = .medal
                rewardScene.launchMedal(symbol: firstMedal.id.symbol) {
                    guard !stopped else { return }
                    HapticsService.medal(level: haptics)
                    celebrate(index: 3)
                    if soundEnabled { AudioServicesPlaySystemSound(1104) }
                }
                try await pause(1.3)
                guard !stopped else { return }
                rewardScene.showFinalMedal(symbol: firstMedal.id.symbol)
                stage = .settled
                try await finishParticles()
                return
            }
            let startDelays: [Double] = [0, 0.25, 0.27]
            for index in 0..<presentation.stars {
                if index > 0 { try await pause(startDelays[index]) }
                guard !stopped else { return }
                rewardScene.launchStar(index) {
                    guard !stopped else { return }
                    starFeedback.impact(index: index)
                    celebrate(index: index)
                }
            }
            try await pause(0.46)
            guard !stopped else { return }
            stage = .xp
            try await countXP()
            guard !stopped else { return }
            if !presentation.didLevelUp {
                HapticsService.finale(level: haptics)
                celebrate(index: 6)
            }
            if let firstMedal = presentation.newMedals.first {
                stage = .medal
                withAnimation(.easeOut(duration: 0.15)) { levelVisible = false }
                rewardScene.launchMedal(symbol: firstMedal.id.symbol) {
                    guard !stopped else { return }
                    HapticsService.medal(level: haptics)
                    celebrate(index: 3)
                }
                try await pause(1.3)
                guard !stopped else { return }
            }
            if presentation.didCompleteTodaysMust {
                stage = .mustClear
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    levelVisible = false
                    mustClearVisible = true
                }
                HapticsService.dailyClear(level: haptics)
                celebrate(index: 5)
                try await pause(0.85)
            }
            if let firstMedal = presentation.newMedals.first {
                rewardScene.showFinalMedal(symbol: firstMedal.id.symbol)
            } else {
                rewardScene.showFinalStars()
            }
            stage = .settled
            // The result is already interactive while the final confetti drifts away.
            try await finishParticles()
        } catch {
            rewardScene.stop()
        }
    }

    private func countXP() async throws {
        let steps = LevelFillStep.steps(from: presentation.previousXP, to: presentation.totalXP)
        var added = 0
        for step in steps {
            displayedLevel = step.level
            displayedLevelXP = Double(step.fromXP)
            let gain = step.toXP - step.fromXP
            let frames = max(1, Int((32 * Double(gain) / Double(max(1, presentation.xp))).rounded()))
            for frame in 1...frames {
                try await pause(0.017)
                let fraction = Double(frame) / Double(frames)
                let ease = 1 - pow(1 - fraction, 3)
                displayedLevelXP = Double(step.fromXP) + Double(gain) * ease
                let previousTick = shownXP * 4 / max(1, presentation.xp)
                shownXP = added + Int((Double(gain) * ease).rounded())
                if shownXP * 4 / max(1, presentation.xp) > previousTick {
                    HapticsService.xpTick(level: haptics)
                }
            }
            added += gain
            displayedLevelXP = Double(step.toXP)
            shownXP = added
            if step.reachesNextLevel {
                // Keep 250/250 visible while celebrating; only then empty the
                // bar and animate the remaining XP into the following level.
                stage = .level
                withAnimation(.spring(response: 0.36, dampingFraction: 0.55)) { levelVisible = true }
                HapticsService.levelUp(level: haptics)
                celebrate(index: 4)
                // Let the level-up's final sustain finish before the next reward.
                try await pause(haptics == .off ? 0.6 : max(0.6, HapticsService.duration(for: .levelUp) + 0.08))
                displayedLevel = step.level + 1
                displayedLevelXP = 0
            }
        }
        shownXP = presentation.xp
        displayedLevel = presentation.totalXP / 250 + 1
        displayedLevelXP = Double(presentation.totalXP % 250)
    }

    private func celebrate(index: Int) {
        guard !stopped, !motionReduced else { return }
        let now = Date()
        bursts.removeAll { now.timeIntervalSince($0.time) >= RewardParticles.lifetime }
        bursts.append(RewardBurst(index: index, time: now))
        if index >= 3 { rewardBeat += 1 }
    }

    private func finishParticles() async throws {
        if let last = bursts.last {
            try await pause(max(0, RewardParticles.lifetime - Date().timeIntervalSince(last.time)))
        }
        particlesActive = false
        bursts.removeAll()
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .milliseconds(Int(seconds * 1_000)))
        if stopped { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func settleImmediately() {
        stopped = true
        starFeedback.stop()
        HapticsService.stop()
        if presentation.stars == 0, let firstMedal = presentation.newMedals.first {
            rewardScene.showFinalMedal(symbol: firstMedal.id.symbol)
        } else {
            rewardScene.showFinalStars()
        }
        shownXP = presentation.xp
        displayedLevel = presentation.totalXP / 250 + 1
        displayedLevelXP = Double(presentation.totalXP % 250)
        levelVisible = false
        mustClearVisible = presentation.didCompleteTodaysMust
        particlesActive = false
        bursts.removeAll()
        stage = .settled
    }
}

private enum RewardStage { case stars, xp, level, medal, mustClear, settled }

private struct RewardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

private struct RewardBackdrop: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DopaTheme.background
                if contrast != .increased {
                    Image("RewardBackground")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    LinearGradient(
                        colors: [.black.opacity(0.12), .clear, DopaTheme.background.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RewardBurst: Identifiable {
    let id = UUID()
    let index: Int
    let time: Date
}

/// One bounded canvas for screen-wide cannons, firework trails and impact rings.
private struct RewardParticles: View {
    static let lifetime = 3.2
    let bursts: [RewardBurst]
    let active: Bool
    private let colors: [Color] = [.yellow, .cyan, .pink, .orange, .mint, .white, .purple]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || bursts.isEmpty)) { timeline in
            Canvas { context, size in
                guard active else { return }
                for burst in bursts {
                    let elapsed = timeline.date.timeIntervalSince(burst.time)
                    guard elapsed >= 0, elapsed < Self.lifetime else { continue }
                    confetti(context: context, size: size, burst: burst, elapsed: elapsed)
                    if burst.index >= 2 {
                        fireworks(context: context, size: size, burst: burst, elapsed: elapsed)
                    }
                    impactRing(context: context, size: size, burst: burst, elapsed: elapsed)
                }
            }
        }
    }

    private func confetti(context: GraphicsContext, size: CGSize, burst: RewardBurst, elapsed: Double) {
        let big = burst.index >= 3
        let count = big ? (burst.index == 5 ? 140 : 100) : 32 + burst.index * 14
        let fade = min(1, max(0, (Self.lifetime - elapsed) / 0.9))
        for particle in 0..<count {
            let seed = Double(particle * 137 + burst.index * 71)
            let fromLeft = particle.isMultiple(of: 2)
            let launchDelay = Double(particle % 5) * 0.035
            let t = elapsed - launchDelay
            guard t >= 0 else { continue }
            let originX = fromLeft ? -8.0 : size.width + 8
            let velocityX = (size.width * (0.22 + seed.truncatingRemainder(dividingBy: 80) / 120)) * (fromLeft ? 1 : -1)
            let velocityY = -(170 + seed.truncatingRemainder(dividingBy: 180))
            let x = originX + velocityX * t * 0.72 + sin(t * 5 + seed) * 9
            let y = size.height * (big ? 0.48 : 0.38) + velocityY * t + 140 * t * t
            let width = 4 + seed.truncatingRemainder(dividingBy: 5)
            var piece = context
            piece.opacity = fade * (big ? 0.95 : 0.8)
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .degrees(seed + t * 250))
            piece.scaleBy(x: 0.4 + abs(cos(t * 7 + seed)) * 0.6, y: 1)
            let rect = CGRect(x: -width / 2, y: -width, width: width, height: width * 1.8)
            let path = particle.isMultiple(of: 4) ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1)
            piece.fill(path, with: .color(colors[particle % colors.count]))
        }
    }

    private func fireworks(context: GraphicsContext, size: CGSize, burst: RewardBurst, elapsed: Double) {
        let big = burst.index >= 3
        let centers: [CGPoint] = big
            ? [.init(x: 0.22, y: 0.20), .init(x: 0.80, y: 0.30), .init(x: 0.50, y: 0.13)]
            : [.init(x: 0.5, y: 0.28)]
        for (bloom, center) in centers.enumerated() {
            let t = elapsed - Double(bloom) * 0.20
            guard t >= 0, t < 1.45 else { continue }
            let progress = t / 1.45
            let radius = min(size.width * 0.36, 145) * (1 - pow(1 - progress, 3))
            let origin = CGPoint(x: size.width * center.x, y: size.height * center.y + 32 * t * t)
            let color = colors[(burst.index + bloom * 2) % colors.count]
            var glow = context
            glow.opacity = pow(1 - progress, 1.4)
            for ray in 0..<32 {
                let angle = Double(ray) * .pi / 16 + Double(bloom) * 0.2
                let length = radius * (ray.isMultiple(of: 2) ? 1 : 0.73)
                var trail = Path()
                trail.move(to: .init(x: origin.x + cos(angle) * length * 0.65, y: origin.y + sin(angle) * length * 0.65))
                trail.addLine(to: .init(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length))
                glow.stroke(trail, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                let spark = CGRect(x: origin.x + cos(angle) * length - 1.8, y: origin.y + sin(angle) * length - 1.8, width: 3.6, height: 3.6)
                glow.fill(Path(ellipseIn: spark), with: .color(.white))
            }
        }
    }

    private func impactRing(context: GraphicsContext, size: CGSize, burst: RewardBurst, elapsed: Double) {
        guard elapsed < 0.55 else { return }
        let progress = elapsed / 0.55
        let radius = 18 + progress * size.width * 0.58
        let origin = CGPoint(x: size.width / 2, y: size.height * 0.34)
        var wave = context
        wave.opacity = (1 - progress) * 0.65
        let ring = Path(ellipseIn: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
        wave.stroke(ring, with: .color(burst.index == 5 ? .mint : .yellow), lineWidth: 4 * (1 - progress) + 1)
    }
}
