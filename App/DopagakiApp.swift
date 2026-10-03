import SwiftUI
import DopagakiCore

@main
@MainActor
struct DopagakiApp: App {
    @StateObject private var store = AppStore()
    init() { _ = WatchSyncService.shared }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

private struct RootSheet: Identifiable {
    enum Kind: Equatable { case note, detail }
    let occurrenceID: UUID
    let kind: Kind
    var id: String { "\(kind)-\(occurrenceID)" }
}

@MainActor
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var sheet: RootSheet?
    @State private var pendingRecord: UUID?
    @State private var presentedCompletion: CompletionPresentation?
    @State private var pendingCompletion: CompletionPresentation?
    @State private var presentationTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $tab) {
            TodayView().tabItem { Label("今日", systemImage: "bolt.fill") }.tag(0)
            ListsView().tabItem { Label("マイリスト", systemImage: "square.grid.2x2.fill") }.tag(1)
            ActivityView().tabItem { Label("記録・実績", systemImage: "chart.bar.xaxis") }.tag(2)
            SettingsView().tabItem { Label("設定", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .tint(DopaTheme.green)
        .onOpenURL { url in
            let scheme = Bundle.main.object(forInfoDictionaryKey: "DopaURLScheme") as? String ?? "dopagaki"
            guard url.scheme == scheme, url.host == "today" else { return }
            store.refreshToday()
            tab = 0
        }
        .fullScreenCover(item: $presentedCompletion, onDismiss: {
            store.completion = nil
            if let id = pendingRecord {
                pendingRecord = nil
                sheet = RootSheet(occurrenceID: id, kind: .note)
            }
        }) { presentation in
            CompletionView(presentation: presentation, haptics: store.state.settings.haptics,
                           soundEnabled: store.state.settings.soundEnabled,
                           reduceMotion: store.state.settings.reduceMotion,
                           onClose: { presentedCompletion = nil },
                           onRecord: { pendingRecord = presentation.occurrenceID; presentedCompletion = nil })
        }
        .sheet(item: $sheet, onDismiss: {
            if let pending = pendingCompletion {
                pendingCompletion = nil
                presentedCompletion = pending
            }
        }) { target in
            NavigationStack {
                if target.kind == .note {
                    ScrollView {
                        NoteComposer(occurrenceID: target.occurrenceID).padding(20)
                    }
                    .navigationTitle("取り組みを記録")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { sheet = nil } } }
                    .dopaPage()
                } else { TaskDetailView(occurrenceID: target.occurrenceID) }
            }
            .environmentObject(store)
        }
        .alert("お知らせ", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK") { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
        .onChange(of: scenePhase) { _, value in
            if value == .active { store.refreshToday() }
        }
        .onChange(of: store.notificationOccurrenceID, initial: true) { _, id in
            guard let id else { return }
            tab = 0
            sheet = RootSheet(occurrenceID: id, kind: .detail)
            store.notificationOccurrenceID = nil
        }
        .onChange(of: store.completion?.id) { _, id in
            guard id != nil, let saved = store.completion else { return }
            presentationTask?.cancel()
            // Data is already saved. Allow child sheets/navigation to dismiss before celebrating.
            presentationTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard store.completion?.id == saved.id else { return }
                if sheet != nil {
                    pendingCompletion = saved
                    sheet = nil
                } else { presentedCompletion = saved }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                if scenePhase == .active { store.refreshToday() }
            }
        }
    }
}
