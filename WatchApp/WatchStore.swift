import Foundation
import Combine
import WatchConnectivity
import WidgetKit
import DopagakiCore

@MainActor
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()
    @Published private(set) var transfer: WatchProgressTransfer?
    @Published private(set) var message = "iPhoneでドパガキを開いてください。"
    @Published private(set) var requesting = false
    private let session = WCSession.default
    private var requestID: UUID?

    private override init() {
        super.init()
        transfer = try? WatchProgressRepository().load()
        session.delegate = self
        session.activate()
    }

    func refresh() {
        transfer = try? WatchProgressRepository().load()
        guard session.activationState == .activated else {
            message = "iPhoneとの接続を準備しています。"
            return
        }
        // isReachable can be false while a current context is still available locally.
        receive(session.receivedApplicationContext)
        guard session.isReachable else {
            message = "iPhoneでドパガキを開くと、次の接続時に更新します。"
            return
        }
        guard !requesting else { return }
        requesting = true
        let id = UUID()
        requestID = id
        message = "iPhoneに確認中…"
        session.sendMessage([WatchProgressTransfer.requestKey: true], replyHandler: { [weak self] reply in
            let received = self?.receive(reply) == true
            Task { @MainActor in self?.finishRequest(id, message: !received ? "iPhoneで一度ドパガキを開いてください。" : "iPhoneの最新の集計を受け取りました。") }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.finishRequest(id, message: "今は接続できません。iPhoneを近くに置いて再度お試しください。") }
        })
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            self?.finishRequest(id, message: "更新を待っています。iPhone側も開いてお試しください。")
        }
    }

    private func finishRequest(_ id: UUID, message: String) {
        guard requestID == id else { return }
        requestID = nil
        requesting = false
        self.message = message
    }

    /// Persist before returning to WCSession so a background task may safely complete.
    @discardableResult private nonisolated func receive(_ context: [String: Any]) -> Bool {
        guard let data = context[WatchProgressTransfer.messageKey] as? Data else { return false }
        do {
            if try WatchProgressRepository().receive(data) {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotRepository.kind)
            }
            Task { @MainActor [weak self] in
                self?.transfer = try? WatchProgressRepository().load()
                self?.message = "iPhoneから更新しました。"
            }
            return true
        } catch {
            Task { @MainActor [weak self] in self?.message = "更新を保存できませんでした。もう一度お試しください。" }
            return false
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        receive(session.receivedApplicationContext)
        Task { @MainActor [weak self] in
            if error != nil { self?.message = "接続できません。iPhoneとのペアリングを確認してください。" }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }
}
