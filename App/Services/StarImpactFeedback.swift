import AVFAudio
import Combine
import CoreHaptics
import DopagakiCore
import UIKit

/// Prepared before flight. Each landing starts audio and haptics on one engine clock.
@MainActor
final class StarImpactFeedback: ObservableObject {
    private var engine: CHHapticEngine?
    private var patterns: [Int: CHHapticPatternPlayer] = [:]
    private var audioPlayers: [Int: AVAudioPlayer] = [:]
    private var fallbackImpacts: [UIImpactFeedbackGenerator] = []
    private var played: Set<Int> = []
    private var level: HapticLevel = .off
    private var ready = false
    private var activatedAudio = false
    private var interruption: AnyCancellable?

    func prepare(level: HapticLevel, soundEnabled: Bool) {
        stop()
        self.level = level
        played.removeAll()
        guard level != .off || soundEnabled else { return }

        var canPlaySound = soundEnabled
        if soundEnabled {
            do {
                let session = AVAudioSession.sharedInstance()
                // Respect Silent Mode and mix with the user's music.
                try session.setCategory(.ambient, mode: .default)
                try session.setActive(true)
                activatedAudio = true
            } catch { canPlaySound = false }
        }
        fallbackImpacts = [UIImpactFeedbackGenerator(style: .medium),
                           UIImpactFeedbackGenerator(style: .heavy),
                           UIImpactFeedbackGenerator(style: .heavy)]
        if level != .off { fallbackImpacts.forEach { $0.prepare() } }
        if canPlaySound {
            for index in 0..<3 {
                guard let url = soundURL(index), let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                player.prepareToPlay()
                audioPlayers[index] = player
            }
        }

        let capabilities = CHHapticEngine.capabilitiesForHardware()
        if capabilities.supportsHaptics {
            do {
                let created = try CHHapticEngine(audioSession: canPlaySound ? .sharedInstance() : nil)
                // Only keep it warm for this short foreground celebration.
                created.isAutoShutdownEnabled = false
                created.resetHandler = { [weak self] in
                    Task { @MainActor in self?.stop() }
                }
                created.stoppedHandler = { [weak self] _ in
                    Task { @MainActor in self?.stop() }
                }
                engine = created
                try created.start()
                for index in 0..<3 {
                    var events = level == .off ? [] : HapticsService.starEvents(index: index)
                    if canPlaySound, capabilities.supportsAudio, let url = soundURL(index) {
                        let resource = try created.registerAudioResource(url, options: [:])
                        events.append(CHHapticEvent(audioResourceID: resource, parameters: [], relativeTime: 0))
                    } else if canPlaySound {
                        // Use the preloaded audio + prepared UIKit fallback together.
                        continue
                    }
                    guard !events.isEmpty else { continue }
                    let pattern = try CHHapticPattern(events: events, parameters: [])
                    let player = try created.makePlayer(with: pattern)
                    try player.sendParameters([
                        CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                 value: HapticsService.factor(level), relativeTime: 0)
                    ], atTime: CHHapticTimeImmediate)
                    patterns[index] = player
                }
            } catch {
                patterns.removeAll()
                engine?.stop(completionHandler: nil)
                engine = nil
            }
        }
        ready = true
        interruption = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                Task { @MainActor in self?.stop() }
            }
    }

    func impact(index: Int) {
        guard ready, (0..<3).contains(index), UIApplication.shared.applicationState == .active,
              played.insert(index).inserted else { return }
        if let player = patterns[index] {
            do {
                try player.start(atTime: CHHapticTimeImmediate)
                return
            } catch { /* Fall back without delaying the landing. */ }
        }
        audioPlayers[index]?.play()
        if level != .off, fallbackImpacts.indices.contains(index) {
            fallbackImpacts[index].impactOccurred(intensity: CGFloat(HapticsService.factor(level)))
        }
    }

    func stop() {
        ready = false
        interruption = nil
        patterns.values.forEach { try? $0.stop(atTime: CHHapticTimeImmediate) }
        patterns.removeAll()
        audioPlayers.values.forEach { $0.stop() }
        audioPlayers.removeAll()
        engine?.stop(completionHandler: nil)
        engine = nil
        fallbackImpacts.removeAll()
        if activatedAudio {
            activatedAudio = false
            let session = AVAudioSession.sharedInstance()
            if session.category == .ambient {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    private func soundURL(_ index: Int) -> URL? {
        Bundle.main.url(forResource: "star-impact-\(index + 1)", withExtension: "wav", subdirectory: "RewardSounds")
    }
}
