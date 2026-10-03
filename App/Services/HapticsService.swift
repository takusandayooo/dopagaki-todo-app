import CoreHaptics
import DopagakiCore
import UIKit

/// Foreground reward feedback. Patterns and visuals share the same impact times.
@MainActor
enum HapticsService {
    private static var engine: CHHapticEngine?
    private static var players: [CHHapticPatternPlayer] = []
    private static var lastSelectionTime: TimeInterval = -.infinity

    static func tap(level: HapticLevel) { play(.tap, level: level) }
    static func success(level: HapticLevel) { play(.success, level: level) }
    static func medal(level: HapticLevel) { play(.medal, level: level) }
    static func levelUp(level: HapticLevel) { play(.levelUp, level: level) }
    static func xpTick(level: HapticLevel) { play(.xpTick, level: level) }
    static func finale(level: HapticLevel) { play(.finale, level: level) }
    static func dailyClear(level: HapticLevel) { play(.dailyClear, level: level) }

    static func starEvents(index: Int) -> [CHHapticEvent] {
        events(for: [.starOne, .starTwo, .starThree][max(0, min(2, index))])
    }

    static func play(_ cue: HapticCue, level: HapticLevel) {
        let heavy: Set<HapticCue> = [.starThree, .levelUp, .medal, .finale, .dailyClear, .targetReached]
        let selection: Set<HapticCue> = [.dateStep, .timeStep, .durationStep]
        play(level: level, events: events(for: cue), fallback: heavy.contains(cue) ? .heavy : selection.contains(cue) ? .rigid : .medium,
             fallbackIntensity: 1)
    }

    /// No queued ticks: fast wheel/stepper changes stay attached to the current value.
    static func selection(_ cue: HapticCue, level: HapticLevel) {
        guard level != .off, UIApplication.shared.applicationState == .active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let minimumInterval = max(0.045, duration(for: cue) + 0.01)
        guard now - lastSelectionTime >= minimumInterval else { return }
        lastSelectionTime = now
        play(cue, level: level)
    }

    static func duration(for cue: HapticCue) -> Double {
        events(for: cue).map { $0.relativeTime + $0.duration }.max() ?? 0
    }

    private static func events(for cue: HapticCue) -> [CHHapticEvent] {
        // Keep the first impact at time zero, including the shared star/audio cue.
        let spacing = cue == .levelUp ? 1.2 : 2.2
        let sustain = cue == .levelUp ? 1.4 : 2.2
        var events = baseEvents(for: cue).map { event in
            if event.type == .hapticContinuous {
                let minimumHold: Double = cue == .dateStep ? 0.08 : cue == .durationStep ? 0.10 : 0
                return CHHapticEvent(eventType: event.type, parameters: event.eventParameters,
                                     relativeTime: event.relativeTime * spacing,
                                     duration: max(minimumHold, event.duration * sustain))
            }
            return CHHapticEvent(eventType: event.type, parameters: event.eventParameters,
                                 relativeTime: event.relativeTime * spacing)
        }
        // A transient has no configurable length, so give its final impact a short body.
        if let last = events.max(by: { $0.relativeTime + $0.duration < $1.relativeTime + $1.duration }),
           last.type == .hapticTransient {
            let tail: Double
            switch cue {
            case .timeStep: tail = 0.09
            case .xpTick: tail = 0.06
            default: tail = 0.12
            }
            let sharpness = last.eventParameters.first { $0.parameterID == .hapticSharpness }?.value ?? 0.3
            events.append(rumble(at: last.relativeTime + 0.008, duration: tail, sharpness: sharpness * 0.4))
        }
        return events
    }

    private static func baseEvents(for cue: HapticCue) -> [CHHapticEvent] {
        switch cue {
        case .dateStep:
            return [hit(at: 0, sharpness: 0.4), rumble(at: 0.006, duration: 0.025, sharpness: 0.15)]
        case .timeStep:
            return [hit(at: 0, sharpness: 0.9)]
        case .durationStep:
            return [hit(at: 0, sharpness: 0.6), rumble(at: 0.008, duration: 0.032, sharpness: 0.2)]
        case .tap:
            return [hit(at: 0, sharpness: 0.55)]
        case .taskSaved:
            return [rumble(at: 0, duration: 0.045, sharpness: 0.1), hit(at: 0.065, sharpness: 0.8)]
        case .mustPinned:
            return [rumble(at: 0, duration: 0.04, sharpness: 0.08), rumble(at: 0.04, duration: 0.04, sharpness: 0.15), rumble(at: 0.08, duration: 0.04, sharpness: 0.25), hit(at: 0.135, sharpness: 0.95)]
        case .checkOn:
            return [hit(at: 0, sharpness: 1)]
        case .checkOff:
            return [rumble(at: 0, duration: 0.04, sharpness: 0.18), rumble(at: 0.04, duration: 0.055, sharpness: 0.05)]
        case .checklistClear:
            return [hit(at: 0, sharpness: 0.75), hit(at: 0.045, sharpness: 0.8), hit(at: 0.11, sharpness: 0.85), hit(at: 0.23, sharpness: 0.65)]
        case .focusStart:
            return [rumble(at: 0, duration: 0.07, sharpness: 0.08), rumble(at: 0.07, duration: 0.07, sharpness: 0.2), rumble(at: 0.14, duration: 0.08, sharpness: 0.4), hit(at: 0.24, sharpness: 0.9)]
        case .focusPause:
            return [rumble(at: 0, duration: 0.07, sharpness: 0.2), rumble(at: 0.07, duration: 0.06, sharpness: 0.1), rumble(at: 0.13, duration: 0.06, sharpness: 0)]
        case .focusResume:
            return [hit(at: 0, sharpness: 0.85), hit(at: 0.035, sharpness: 0.9), hit(at: 0.095, sharpness: 0.95)]
        case .focusExtend:
            return [hit(at: 0, sharpness: 0.85), hit(at: 0.055, sharpness: 0.85), hit(at: 0.11, sharpness: 0.85), hit(at: 0.2, sharpness: 0.45)]
        case .targetReached:
            return [rumble(at: 0, duration: 0.16, sharpness: 0.1), rumble(at: 0.28, duration: 0.2, sharpness: 0.18)]
        case .starOne:
            return [hit(at: 0, sharpness: 0.65), hit(at: 0.075, sharpness: 0.45)]
        case .starTwo:
            return [hit(at: 0, sharpness: 0.7), rumble(at: 0.018, duration: 0.12, sharpness: 0.3)]
        case .starThree:
            return [hit(at: 0, sharpness: 0.8), rumble(at: 0.014, duration: 0.21, sharpness: 0.22), hit(at: 0.245, sharpness: 0.5)]
        case .medal:
            return [hit(at: 0, sharpness: 0.35), rumble(at: 0.012, duration: 0.2, sharpness: 0.08), hit(at: 0.26, sharpness: 0.9), hit(at: 0.30, sharpness: 0.95), hit(at: 0.34, sharpness: 1)]
        case .levelUp:
            return [(0.0, 0.28), (0.44, 0.36), (1.0, 0.50)].flatMap { time, sustain in
                [hit(at: time, sharpness: 0.55), rumble(at: time + 0.012, duration: sustain, sharpness: 0.2)]
            }
        case .xpTick:
            return [hit(at: 0, sharpness: 0.95), hit(at: 0.023, sharpness: 0.95)]
        case .finale:
            return [hit(at: 0, sharpness: 0.7), rumble(at: 0.015, duration: 0.16, sharpness: 0.2), hit(at: 0.2, sharpness: 0.85), hit(at: 0.4, sharpness: 0.9)]
        case .success:
            return [hit(at: 0, sharpness: 0.48), hit(at: 0.09, sharpness: 0.62)]
        case .dailyClear:
            return [hit(at: 0, sharpness: 0.7), hit(at: 0.12, sharpness: 0.65), hit(at: 0.3, sharpness: 0.5), rumble(at: 0.31, duration: 0.18, sharpness: 0.2)]
        }
    }

    static func stop() {
        for player in players { try? player.stop(atTime: CHHapticTimeImmediate) }
        players.removeAll()
    }

    static func factor(_ level: HapticLevel) -> Float {
        switch level {
        case .off: return 0
        case .soft: return 0.38
        case .standard: return 0.95
        case .strong: return 1
        }
    }

    private static func hit(at time: Double, sharpness: Float) -> CHHapticEvent {
        // Every event uses the API maximum; the user-selected level scales the player.
        CHHapticEvent(eventType: .hapticTransient, parameters: [.init(parameterID: .hapticIntensity, value: 1), .init(parameterID: .hapticSharpness, value: sharpness)], relativeTime: time)
    }

    private static func rumble(at time: Double, duration: Double, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [.init(parameterID: .hapticIntensity, value: 1), .init(parameterID: .hapticSharpness, value: sharpness)], relativeTime: time, duration: duration)
    }

    private static func play(level: HapticLevel, events: [CHHapticEvent], fallback: UIImpactFeedbackGenerator.FeedbackStyle, fallbackIntensity: CGFloat) {
        guard level != .off, UIApplication.shared.applicationState == .active else { return }
        let intensity = factor(level)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            UIImpactFeedbackGenerator(style: fallback).impactOccurred(intensity: fallbackIntensity * CGFloat(intensity))
            return
        }
        do {
            if engine == nil {
                let created = try CHHapticEngine()
                created.isAutoShutdownEnabled = true
                created.resetHandler = {
                    Task { @MainActor in engine = nil; players.removeAll() }
                }
                engine = created
            }
            guard let engine else { return }
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0)], atTime: CHHapticTimeImmediate)
            try player.start(atTime: CHHapticTimeImmediate)
            players.append(player)
            // Keep only a small number of recent bounded patterns alive.
            if players.count > 8 { players.removeFirst(players.count - 8) }
        } catch {
            UIImpactFeedbackGenerator(style: fallback).impactOccurred(intensity: fallbackIntensity * CGFloat(intensity))
        }
    }
}

/// Preview and actual interactions use this same catalogue; no random feedback.
enum HapticCue: String, CaseIterable, Identifiable {
    case dateStep, timeStep, durationStep
    case tap, taskSaved, mustPinned, checkOn, checkOff, checklistClear
    case focusStart, focusPause, focusResume, focusExtend, targetReached
    case starOne, starTwo, starThree, xpTick, levelUp, medal, finale, dailyClear, success

    var id: String { rawValue }
    var group: String {
        switch self {
        case .dateStep, .timeStep, .durationStep: return "日付・時間を選ぶ"
        case .tap, .taskSaved, .mustPinned, .checkOn, .checkOff, .checklistClear: return "いつもの操作"
        case .focusStart, .focusPause, .focusResume, .focusExtend, .targetReached: return "集中タイマー"
        default: return "達成のお祝い"
        }
    }
    var title: String {
        switch self {
        case .dateStep: return "日付・曜日を選ぶ"
        case .timeStep: return "時刻を合わせる"
        case .durationStep: return "目標時間・回数を刻む"
        case .tap: return "タップ"
        case .taskSaved: return "タスクを保存"
        case .mustPinned: return "今日のマストに指定"
        case .checkOn: return "チェックを入れる"
        case .checkOff: return "チェックを外す"
        case .checklistClear: return "チェックリスト全完了"
        case .focusStart: return "集中スタート"
        case .focusPause: return "ひと休み"
        case .focusResume: return "集中を再開"
        case .focusExtend: return "時間を延長"
        case .targetReached: return "目標時間に到達"
        case .starOne: return "1つ目の星"
        case .starTwo: return "2つ目の星"
        case .starThree: return "3つ目の星"
        case .xpTick: return "XPが増える"
        case .levelUp: return "レベルアップ"
        case .medal: return "メダル獲得"
        case .finale: return "花火のフィナーレ"
        case .dailyClear: return "今日のマスト全達成"
        case .success: return "記録を保存"
        }
    }
    var rhythm: String {
        switch self {
        case .dateStep: return "コトン · 重みのある日付送り"
        case .timeStep: return "カチッ · はっきりした時計の刻み"
        case .durationStep: return "コトッ · ダイヤルの目盛り"
        case .tap: return "コツッ · 短くはっきり"
        case .taskSaved: return "ムッ、カチッ · 押し込んで留める"
        case .mustPinned: return "スーッ、カチッ · 引き寄せて固定"
        case .checkOn: return "カチッ · はっきりしたクリック"
        case .checkOff: return "フッ · 力が抜ける短い余韻"
        case .checklistClear: return "タタ・タ・タン！ · 小さな達成"
        case .focusStart: return "グーッ、ドン · 力をためてスタート"
        case .focusPause: return "ブル…スッ · なだらかに落ち着く"
        case .focusResume: return "タタタン · 素早く再スタート"
        case .focusExtend: return "チチチ、トン · 時間を足す"
        case .targetReached: return "ブルッ、ブルン · 区切りを知らせる"
        case .starOne: return "ポン、トッ · 小さく跳ねる着地"
        case .starTwo: return "ドン · 重さが加わる"
        case .starThree: return "ブルン、コツ · 最大の着地"
        case .xpTick: return "チリッ · ごく細かな二連打"
        case .levelUp: return "ドン、ドン、ドーン · 3段階で上昇"
        case .medal: return "ズン、チリリ · 重みと細かな余韻"
        case .finale: return "ドン、パン、パン · 花火のリズム"
        case .dailyClear: return "ト、ドン、ブルン！ · 一日の締め"
        case .success: return "トン、ポン · 記録できた合図"
        }
    }
}
