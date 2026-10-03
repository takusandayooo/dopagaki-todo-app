import SwiftUI
import DopagakiCore

struct TaskEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let isEditing: Bool
    @State private var draft: TaskDefinition
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var hasReminder: Bool
    @State private var reminder: Date
    @State private var hasTarget: Bool
    @State private var targetMinutes: Int
    @State private var labels: String
    @State private var newPhotos: [Data] = []
    @State private var showArchive = false

    init(task: TaskDefinition? = nil, listName: String? = nil) {
        let initial = task ?? TaskDefinition(listName: listName ?? "暮らし")
        isEditing = task != nil
        _draft = State(initialValue: initial)
        _hasDeadline = State(initialValue: initial.deadline != nil)
        _deadline = State(initialValue: initial.deadline ?? Date())
        _hasReminder = State(initialValue: initial.reminder != nil)
        _reminder = State(initialValue: initial.reminder ?? Date().addingTimeInterval(3600))
        _hasTarget = State(initialValue: initial.targetMinutes != nil)
        _targetMinutes = State(initialValue: initial.targetMinutes ?? 25)
        _labels = State(initialValue: initial.labels.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VoiceTextInput(text: $draft.title, placeholder: "タスク名", multiline: false)
                    TextField("詳しい内容・最初の一歩", text: $draft.details, axis: .vertical).lineLimit(3...8)
                    Picker("マイリスト", selection: $draft.listName) {
                        ForEach(Array(Set(store.state.listNames + [draft.listName])).sorted(), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Picker("優先度", selection: $draft.priority) {
                        Text("低").tag(TaskPriority.low)
                        Text("中").tag(TaskPriority.normal)
                        Text("高").tag(TaskPriority.high)
                    }
                    Toggle("マストタスク", isOn: $draft.isMust)
                } header: { Text("やること") } footer: {
                    Text("マストは「必ずやること」。繰り返しタスクでは実行日ごとに引き継ぎます。")
                }
                Section("繰り返し") {
                    Picker("頻度", selection: $draft.recurrence.frequency) {
                        Text("繰り返さない").tag(RepeatFrequency.none)
                        Text("毎日").tag(RepeatFrequency.daily)
                        Text("毎週・曜日指定").tag(RepeatFrequency.weekly)
                        Text("毎月").tag(RepeatFrequency.monthly)
                    }
                    if draft.recurrence.frequency == .weekly { weekdayPicker }
                    if draft.recurrence.frequency == .monthly {
                        Picker("毎月の日付", selection: $draft.recurrence.monthDay.selectionTick(.dateStep, level: store.state.settings.haptics)) {
                            ForEach(1...31, id: \.self) { Text("\($0)日").tag($0) }
                        }
                        Text("指定日がない月は、その月の最終日に表示します。")
                            .font(.caption).foregroundStyle(DopaTheme.secondary)
                    }
                }
                Section("期限と目標") {
                    Toggle("期限を設定", isOn: $hasDeadline)
                    if hasDeadline {
                        Toggle("時刻も指定", isOn: $draft.deadlineHasTime)
                        DatePicker("期限", selection: $deadline.dateSelectionTick(calendar: store.state.calendar, includesTime: draft.deadlineHasTime, level: store.state.settings.haptics), displayedComponents: draft.deadlineHasTime ? [.date, .hourAndMinute] : [.date])
                        if draft.recurrence.frequency != .none {
                            Text(draft.deadlineHasTime ? "繰り返す日は、毎回この時刻が期限になります。" : "繰り返す日の終わりを期限にします。")
                                .font(.caption).foregroundStyle(DopaTheme.secondary)
                        }
                    }
                    Toggle("目標時間を決める", isOn: $hasTarget)
                    if hasTarget { Stepper("\(targetMinutes)分", value: $targetMinutes.selectionTick(.durationStep, level: store.state.settings.haptics), in: 1...360, step: 5) }
                }
                Section {
                    Toggle("通知で思い出す", isOn: $hasReminder)
                    if hasReminder {
                        DatePicker("通知日時", selection: $reminder.dateSelectionTick(calendar: store.state.calendar, level: store.state.settings.haptics), displayedComponents: [.date, .hourAndMinute])
                    }
                } header: { Text("リマインダー") } footer: { Text("通知の許可は保存時に確認します。許可しなくてもタスクは保存できます。") }
                Section("チェックリスト") {
                    ForEach($draft.checklist) { $item in
                        HStack {
                            Image(systemName: "circle").foregroundStyle(DopaTheme.secondary)
                            TextField("小さなステップ", text: $item.title)
                            Button { draft.checklist.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                                .buttonStyle(.borderless).accessibilityLabel("チェック項目を削除")
                        }
                    }
                    Button { draft.checklist.append(ChecklistItem()) } label: { Label("ステップを追加", systemImage: "plus") }
                }
                Section("ラベル・写真") {
                    TextField("ラベルをカンマで区切る", text: $labels)
                    if !draft.photoNames.isEmpty {
                        StoredPhotos(names: draft.photoNames)
                        Button("既存の写真をすべて外す", role: .destructive) { draft.photoNames = [] }
                    }
                    NewPhotosPicker(photos: $newPhotos)
                }
                if isEditing {
                    Section {
                        Button("タスクをアーカイブ", role: .destructive) { showArchive = true }
                    } footer: { Text("今日の一覧から外します。過去の取り組み記録は残ります。") }
                }
                if let error = store.lastError {
                    Section { Text(error).font(.caption).foregroundStyle(.orange) }
                }
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(DopaTheme.surface)
            .navigationTitle(isEditing ? "タスクを編集" : "新しいタスク")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }.bold()
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (draft.recurrence.frequency == .weekly && draft.recurrence.weekdays.isEmpty))
                }
            }
            .confirmationDialog("このタスクをアーカイブしますか？", isPresented: $showArchive, titleVisibility: .visible) {
                Button("アーカイブ", role: .destructive) {
                    store.archiveTask(draft.id)
                    if store.lastError == nil { dismiss() }
                }
            }
            .onChange(of: draft.recurrence.frequency) { _, value in
                if value == .weekly && draft.recurrence.weekdays.isEmpty { draft.recurrence.weekdays = [store.state.calendar.component(.weekday, from: Date())] }
            }
            .dopaPage()
            .environment(\.calendar, store.state.calendar)
            .environment(\.timeZone, store.state.calendar.timeZone)
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("曜日を選ぶ").font(.subheadline)
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { day in
                    let selected = draft.recurrence.weekdays.contains(day)
                    Button {
                        if selected { draft.recurrence.weekdays.removeAll { $0 == day } }
                        else { draft.recurrence.weekdays.append(day) }
                        HapticsService.selection(.dateStep, level: store.state.settings.haptics)
                    } label: {
                        Text(["日", "月", "火", "水", "木", "金", "土"][day - 1])
                            .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                            .background(selected ? DopaTheme.green : DopaTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(selected ? DopaTheme.background : .white)
                    }.buttonStyle(.borderless).accessibilityLabel("\(["日", "月", "火", "水", "木", "金", "土"][day - 1])曜日、\(selected ? "選択中" : "未選択")")
                }
            }
            if draft.recurrence.weekdays.isEmpty { Text("1つ以上の曜日を選択してください。") .font(.caption).foregroundStyle(.orange) }
        }
    }

    private func save() {
        var task = draft
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.deadline = hasDeadline ? deadline : nil
        task.reminder = hasReminder ? reminder : nil
        task.targetMinutes = hasTarget ? targetMinutes : nil
        task.labels = labels.components(separatedBy: CharacterSet(charactersIn: ",、\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        task.checklist.removeAll { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !newPhotos.isEmpty {
            let names = store.saveTaskPhotos(newPhotos)
            guard names.count == newPhotos.count else { return }
            task.photoNames.append(contentsOf: names)
        }
        store.addOrUpdateTask(task)
        if store.lastError == nil { dismiss() }
    }
}
