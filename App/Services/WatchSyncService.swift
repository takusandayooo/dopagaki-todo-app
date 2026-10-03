import Foundation
import WatchConnectivity
import DopagakiCore

@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()
    private let session: WCSession?
    private var latest: WidgetProgressSnapshot?

    private override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        if let state = try? StateRepository().load() { latest = WidgetProgressSnapshot(state: state, at: Date()) }
        session?.delegate = self
        session?.activate()
    }

    func publish(_ snapshot: WidgetProgressSnapshot) {
        latest = snapshot
        sendLatest()
    }

    @discardableResult private func sendLatest(force: Bool = false) -> Data? {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled, let latest else { return nil }
        let previous = (session.applicationContext[WatchProgressTransfer.messageKey] as? Data)
            .flatMap { try? WatchProgressTransfer.decode($0) }
        if !force, previous?.snapshot == latest { return session.applicationContext[WatchProgressTransfer.messageKey] as? Data }
        // Preserve ordering even if the phone clock was adjusted backwards.
        let updatedAt = max(Date(), previous?.updatedAt.addingTimeInterval(0.001) ?? .distantPast)
        let transfer = WatchProgressTransfer(snapshot: latest, updatedAt: updatedAt)
        guard let data = try? JSONEncoder().encode(transfer) else { return nil }
        do { try session.updateApplicationContext([WatchProgressTransfer.messageKey: data]) }
        catch { /* Retry the background context on the next commit/activation. */ }
        // An immediate reply can still deliver fresh data if queuing the context failed.
        return data
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in self?.sendLatest(force: true) }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.sendLatest(force: true) }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[WatchProgressTransfer.requestKey] as? Bool == true else { replyHandler([:]); return }
        Task { @MainActor [weak self] in
            guard let state = try? StateRepository().load() else { replyHandler([:]); return }
            self?.latest = WidgetProgressSnapshot(state: state, at: Date())
            guard let data = self?.sendLatest() else { replyHandler([:]); return }
            replyHandler([WatchProgressTransfer.messageKey: data])
        }
    }
}
