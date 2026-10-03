import SwiftUI
import DopagakiCore

struct TaskDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let occurrenceID: UUID
    @State private var showEditor = false
    @State private var showSetup = false
    @State private var showFocus = false
    @State private var isCompleting = false
    private var occurrence: TaskOccurrence? { store.state.occurrences.first { $0.id == occurrenceID } }
    private var definition: TaskDefinition? { occurrence.flatMap { occurrence in store.state.tasks.first { $0.id == occurrence.taskID } } }

    var body: some View {
        ScrollView {
            if let occurrence {
                VStack(alignment: .leading, spacing: 24) {
                    titleCard(occurrence)
                    if let definition {
                        if !definition.details.isEmpty {
                            DopaCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    DopaSectionTitle(title: "やること")
                                    Text(definition.details).font(.body).textSelection(.enabled)
                                }
                            }
                        }
                        if !occurrence.checklist.isEmpty { checklistCard(occurrence) }
                        if !definition.photoNames.isEmpty {
                            DopaCard { StoredPhotos(names: definition.photoNames) }
                        }
                    }
                    if !occurrence.isCompleted { actions(occurrence) }
                    NoteComposer(occurrenceID: occurrenceID)
                    DopaSectionTitle(title: "取り組みの記録", detail: DopaTheme.duration(totalTime))
                    if entries.isEmpty {
                        Text("始めた時間、メモ、写真がここに積み重なります。")
                            .font(.subheadline).foregroundStyle(DopaTheme.secondary).padding(.vertical, 15)
                    } else {
                        ForEach(entries) { entry in recordEntry(entry) }
                    }
                }.padding(20).padding(.bottom, 20)
            } else { DopaEmptyState(symbol: "tray", title: "タスクが見つかりません", message: "今日の画面から、別のタスクを選んでください。") }
        }
        .navigationTitle("タスク詳細").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if definition != nil { Button("編集") { showEditor = true } }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let definition { TaskEditorView(task: definition) }
        }
        .sheet(isPresented: $showSetup) {
            if let occurrence {
                FocusSetupView(occurrence: occurrence) {
                    showSetup = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showFocus = true }
                }
            }
        }
        .sheet(isPresented: $showFocus) { FocusView() }
        .dopaPage()
        .environment(\.calendar, store.state.calendar)
        .environment(\.timeZone, store.state.calendar.timeZone)
    }

    private func titleCard(_ occurrence: TaskOccurrence) -> some View {
        DopaCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(definition?.listName ?? "タスク").font(.caption.bold()).foregroundStyle(DopaTheme.green)
                    Spacer()
                    if occurrence.isCompleted { Label("完了", systemImage: "checkmark.seal.fill").font(.caption.bold()).foregroundStyle(DopaTheme.green) }
                }
                Text(occurrence.title).font(.system(.largeTitle, design: .rounded, weight: .heavy))
                if let definition {
                    HStack(spacing: 14) {
                        Label(priorityLabel(definition.priority), systemImage: "flag.fill")
                        Label(recurrenceLabel(definition.recurrence), systemImage: "repeat")
                    }.font(.caption.bold()).foregroundStyle(DopaTheme.secondary)
                    if !definition.labels.isEmpty {
                        Text(definition.labels.map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundStyle(DopaTheme.secondary)
                    }
                    if let deadline = occurrence.deadline {
                        Label {
                            Text(deadline, format: definition.deadlineHasTime ? .dateTime.month().day().hour().minute() : .dateTime.month().day())
                        } icon: { Image(systemName: "calendar") }
                        .font(.subheadline).foregroundStyle(DopaTheme.secondary)
                    }
                }
                if let completedAt = occurrence.completedAt {
                    Text("\(completedAt.formatted(.dateTime.month().day().hour().minute()))に完了")
                        .font(.caption).foregroundStyle(DopaTheme.secondary)
                    if let receipt = store.state.rewards.first(where: { $0.occurrenceID == occurrenceID }) {
                        HStack(spacing: 4) {
                            ForEach(0..<receipt.stars, id: \.self) { _ in Image(systemName: "star.fill").foregroundStyle(DopaTheme.gold) }
                            Spacer()
                            Text("＋\(receipt.xp) XP").font(.headline).foregroundStyle(DopaTheme.gold)
                        }
                    }
                } else {
                    Toggle(isOn: Binding(get: { occurrence.isMust }, set: { store.setMust(occurrenceID, $0) })) {
                        Label(store.today.contains { $0.id == occurrence.id } ? "今日のマスト" : "この実行分のマスト", systemImage: "bolt.fill")
                            .font(.headline).foregroundStyle(DopaTheme.gold)
                    }
                    if occurrence.dayKey != store.state.dayKey(for: Date()) && (definition?.recurrence.frequency ?? .none) != .none {
                        Text("過去の実行分です。今日のタスクは「今日」から選べます。")
                            .font(.caption).foregroundStyle(DopaTheme.secondary)
                    }
                }
            }
        }
    }

    private func checklistCard(_ occurrence: TaskOccurrence) -> some View {
        DopaCard {
            VStack(alignment: .leading, spacing: 15) {
                DopaSectionTitle(title: "小さなステップ", detail: "\(occurrence.checklist.filter(\.isDone).count) / \(occurrence.checklist.count)")
                if occurrence.checklist.allSatisfy(\.isDone) {
                    Label("ステップを全部クリア！", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold()).foregroundStyle(DopaTheme.green)
                }
                ForEach(occurrence.checklist) { item in
                    Button {
                        store.setChecklistItem(occurrenceID: occurrenceID, itemID: item.id, isDone: !item.isDone)
                    } label: {
                        HStack(spacing: 12) {
                            checklistMark(isDone: item.isDone)
                            Text(item.title).strikethrough(item.isDone).foregroundStyle(item.isDone ? DopaTheme.secondary : .white)
                            Spacer()
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(occurrence.isCompleted)
                        .accessibilityLabel("\(item.title)、\(item.isDone ? "完了" : "未完了")")
                }
            }
        }
    }

    @ViewBuilder
    private func checklistMark(isDone: Bool) -> some View {
        let mark = Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
            .font(.title2).foregroundStyle(isDone ? DopaTheme.green : DopaTheme.secondary)
        if systemReduceMotion || store.state.settings.reduceMotion {
            mark
        } else {
            mark.symbolEffect(.bounce, options: .nonRepeating, value: isDone)
        }
    }

    private func actions(_ occurrence: TaskOccurrence) -> some View {
        VStack(spacing: 16) {
            Button {
                if store.state.activeFocus != nil { showFocus = true } else { showSetup = true }
            } label: { Label(store.state.activeFocus == nil ? "このタスクを始める" : "進行中の計測に戻る", systemImage: "play.fill") }
                .buttonStyle(DopaGlassButtonStyle(color: DopaTheme.green, foreground: DopaTheme.background))
            Button {
                guard !isCompleting else { return }
                isCompleting = true
                store.complete(occurrenceID)
                if store.lastError == nil { dismiss() }
                else { isCompleting = false }
            } label: { Label("計測せずに完了", systemImage: "checkmark") }
                .buttonStyle(DopaGlassButtonStyle(color: DopaTheme.surface, prominent: false)).disabled(isCompleting)
        }
    }

    private var totalTime: Double { store.state.sessions.filter { $0.occurrenceID == occurrenceID }.reduce(0) { $0 + $1.duration } }
    private var entries: [TaskRecordEntry] {
        let sessions = store.state.sessions.filter { $0.occurrenceID == occurrenceID }.map { TaskRecordEntry.session($0) }
        let notes = store.state.notes.filter { $0.occurrenceID == occurrenceID }.map { TaskRecordEntry.note($0) }
        return (sessions + notes).sorted { $0.date > $1.date }
    }

    private func recordEntry(_ entry: TaskRecordEntry) -> some View {
        DopaCard {
            VStack(alignment: .leading, spacing: 13) {
                Text(entry.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(DopaTheme.secondary)
                switch entry {
                case .session(let session):
                    Label(DopaTheme.duration(session.duration) + "取り組みました", systemImage: "timer").font(.headline).foregroundStyle(DopaTheme.green)
                case .note(let note):
                    if !note.text.isEmpty { Text(note.text).textSelection(.enabled) }
                    StoredPhotos(names: note.photoNames)
                }
            }
        }
    }
}

private enum TaskRecordEntry: Identifiable {
    case session(FocusSession), note(ActivityNote)
    var id: String {
        switch self { case .session(let value): return "session-\(value.id)"; case .note(let value): return "note-\(value.id)" }
    }
    var date: Date {
        switch self { case .session(let value): return value.endedAt; case .note(let value): return value.createdAt }
    }
}
