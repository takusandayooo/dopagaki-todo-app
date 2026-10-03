import DeviceActivity
import ManagedSettings
import Foundation
import DopagakiCore

final class ActivityMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        refresh()
    }
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Daily restrictions persist across the schedule's one-minute gap.
        if activity == ScreenTimePolicy.escapeActivity { refresh() }
    }
    private func refresh() {
        guard AppConfiguration.sharedDirectory != nil else { return }
        do {
            let policy = try ScreenTimePolicy.load()
            let snapshot = try StateRepository().load()
            policy.apply(to: snapshot)
        } catch {
            // A damaged snapshot must not impose an unexplained lock.
            ManagedSettingsStore(named: ScreenTimePolicy.storeName).clearAllSettings()
        }
    }
}
