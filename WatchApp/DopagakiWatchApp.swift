import SwiftUI
import WatchKit
import WatchConnectivity
import DopagakiCore

@main
struct DopagakiWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var store = WatchStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let progress = store.transfer?.snapshot.progress(at: context.date) {
                                Label("今日のマスト", systemImage: "bolt.fill").foregroundStyle(.yellow).font(.headline)
                                Text(progress.headline).font(.system(.title2, design: .rounded, weight: .heavy))
                                ProgressView(value: progress.progress).tint(.yellow)
                                Text("\(progress.mustCompleted) / \(progress.mustTotal) 個 達成").font(.caption)
                                HStack {
                                    Label("Lv.\(progress.level)", systemImage: "star.fill").foregroundStyle(.yellow)
                                    Spacer()
                                    Text("あと\(progress.xpToNextLevel) XP").font(.caption)
                                }
                                Text("全タスク あと\(progress.taskRemaining)個").font(.caption)
                            } else {
                                Image(systemName: "iphone.and.arrow.forward").font(.largeTitle).foregroundStyle(.yellow)
                                Text("iPhoneから更新しよう").font(.headline)
                                Text("iPhoneでドパギキを開くと、今日の残り件数がここに届きます。").font(.caption)
                            }
                            if let updated = store.transfer?.updatedAt {
                                Text("最終同期 \(updated.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Button {
                                store.refresh()
                            } label: {
                                Label(store.requesting ? "確認中…" : "iPhoneから更新", systemImage: "arrow.clockwise")
                            }
                            .disabled(store.requesting)
                            Text(store.message).font(.caption2).foregroundStyle(.secondary)
                            Text("タスクの完了はiPhoneで。") .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .navigationTitle("ドパギキ")
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.refresh() } }
                .task { store.refresh() }
            }
        }
    }
}

/// Watch Connectivity may wake the app without showing a scene.
@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    private var tasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var activation: NSKeyValueObservation?
    private var pending: NSKeyValueObservation?

    func applicationDidFinishLaunching() {
        _ = WatchStore.shared
        let session = WCSession.default
        activation = session.observe(\.activationState) { [weak self] _, _ in
            Task { @MainActor in self?.completeIfReady() }
        }
        pending = session.observe(\.hasContentPending) { [weak self] _, _ in
            Task { @MainActor in self?.completeIfReady() }
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        _ = WatchStore.shared
        for task in backgroundTasks {
            if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask { tasks.append(connectivity) }
            else { task.setTaskCompletedWithSnapshot(false) }
        }
        completeIfReady()
    }

    private func completeIfReady() {
        let session = WCSession.default
        guard session.activationState != .activated || !session.hasContentPending else { return }
        tasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
        tasks.removeAll()
    }
}
