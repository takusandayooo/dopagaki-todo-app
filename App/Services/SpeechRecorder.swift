import Foundation
import Combine
import Speech
import AVFoundation

@MainActor
final class SpeechRecorder: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var hasTap = false
    private var generation = UUID()
    private var requesting = false
    private var prefix = ""

    func start() async {
        guard !isRecording, !requesting else { return }
        requesting = true
        defer { requesting = false }
        let attempt = UUID()
        generation = attempt
        errorMessage = nil
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard generation == attempt else { return }
        guard speechAllowed else { errorMessage = "音声認識を許可すると、話して記録できます。手入力も使えます。"; return }
        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard generation == attempt else { return }
        guard microphoneAllowed else { errorMessage = "マイクの許可が必要です。設定から変更するか、手入力で記録してください。"; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")), recognizer.isAvailable else {
            errorMessage = "音声認識を利用できません。通信状態を確認するか、手入力で記録してください。"; return
        }
        cleanup(cancelRecognition: true)
        let token = generation
        prefix = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let audioRequest = SFSpeechAudioBufferRecognitionRequest()
            audioRequest.shouldReportPartialResults = true
            audioRequest.taskHint = .dictation
            audioRequest.addsPunctuation = true
            // Prefer local recognition when this device/language supports it.
            audioRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request = audioRequest
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "SpeechRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "マイクを利用できません。"])
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in audioRequest.append(buffer) }
            hasTap = true
            recognition = recognizer.recognitionTask(with: audioRequest) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        self.transcript = self.prefix.isEmpty ? text : self.prefix + "\n" + text
                        if result.isFinal { self.cleanup(cancelRecognition: false) }
                    }
                    if let error {
                        if self.isRecording { self.errorMessage = "認識を終了しました：\(error.localizedDescription)。入力済みの文字は残っています。" }
                        self.cleanup(cancelRecognition: false)
                    }
                }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            cleanup(cancelRecognition: true)
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isRecording else {
            generation = UUID()
            cleanup(cancelRecognition: true)
            return
        }
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        recognition?.finish()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let token = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.generation == token, !self.isRecording else { return }
            self.cleanup(cancelRecognition: true)
        }
    }

    private func cleanup(cancelRecognition: Bool) {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        if cancelRecognition { recognition?.cancel() }
        recognition = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
