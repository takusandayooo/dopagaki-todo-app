import SwiftUI
import DopagakiCore

struct ListsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: String? = nil
    @State private var search = ""
    @State private var showEditor = false
    @State private var editingTask: TaskDefinition?
    @State private var showNewList = false
    @State private var newListName = ""
    private var tasks: [TaskDefinition] {
        store.state.tasks.filter { !$0.archived && (selection == nil || $0.listName == selection) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.labels.contains { $0.localizedCaseInsensitiveContains(search) }) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("続けたいこと、まとめよう。").font(.title2.bold())
                        Text("英語も、仕事も、暮らしも。自分のリストで。")
                            .font(.subheadline).foregroundStyle(DopaTheme.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            listChip("すべて", value: nil)
                            ForEach(store.state.listNames, id: \.self) { name in listChip(name, value: name) }
                            Button { newListName = ""; showNewList = true } label: { Image(systemName: "plus").font(.headline).frame(width: 44, height: 44).background(DopaTheme.elevated, in: Circle()) }
                                .accessibilityLabel("マイリストを追加")
                        }
                    }
                    HStack {
                        Text(selection ?? "すべてのタスク").font(.title3.bold())
                        Spacer()
                        Text("\(tasks.count)件").font(.caption.bold()).foregroundStyle(DopaTheme.secondary)
                    }
                    if tasks.isEmpty {
                        DopaEmptyState(symbol: "square.stack.3d.up", title: search.isEmpty ? "ここから始めよう" : "タスクが見つかりません", message: search.isEmpty ? "毎日続けたいことや、今日のやることを追加できます。" : "別の名前やラベルで検索してください。")
                    }
                    ForEach(tasks) { task in
                        if let occurrence = latestOccurrence(task.id) {
                            NavigationLink { TaskDetailView(occurrenceID: occurrence.id) } label: { taskCard(task, occurrence: occurrence) }
                                .buttonStyle(.plain)
                        } else {
                            Button { editingTask = task } label: { taskCard(task, occurrence: nil) }.buttonStyle(.plain)
                        }
                    }
                }.padding(20).padding(.bottom, 20)
            }
            .searchable(text: $search, prompt: "タスク名・ラベルで探す")
            .navigationTitle("マイリスト")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditor = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel("タスクを追加")
                }
            }
            .sheet(isPresented: $showEditor) {
                TaskEditorView(listName: selection ?? store.state.listNames.first ?? "暮らし")
            }
            .sheet(item: $editingTask) { task in TaskEditorView(task: task) }
            .alert("新しいマイリスト", isPresented: $showNewList) {
                TextField("リストの名前", text: $newListName)
                Button("追加") {
                    let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.addList(name)
                    if !name.isEmpty { selection = name }
                }
                Button("キャンセル", role: .cancel) { }
            } message: { Text("英語、読書、運動など、自由に名前をつけよう。") }
            .dopaPage()
        }
    }

    private func latestOccurrence(_ taskID: UUID) -> TaskOccurrence? {
        store.today.first { $0.taskID == taskID } ?? store.state.occurrences.filter { $0.taskID == taskID }.max { $0.scheduledDate < $1.scheduledDate }
    }

    private func listChip(_ label: String, value: String?) -> some View {
        let selected = value == selection
        return Button { selection = value } label: {
            Text(label).font(.subheadline.bold()).padding(.horizontal, 19).frame(minHeight: 44)
                .background(selected ? DopaTheme.green : DopaTheme.surface, in: Capsule())
                .foregroundStyle(selected ? DopaTheme.background : .white)
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func taskCard(_ task: TaskDefinition, occurrence: TaskOccurrence?) -> some View {
        DopaCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: task.recurrence.frequency == .none ? "square.and.pencil" : "arrow.triangle.2.circlepath")
                    .font(.title2).foregroundStyle(task.recurrence.frequency == .none ? DopaTheme.blue : DopaTheme.green)
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 9) {
                    Text(task.title).font(.headline)
                    HStack(spacing: 8) {
                        Text(task.listName)
                        Text(recurrenceLabel(task.recurrence)).foregroundStyle(DopaTheme.green)
                        if occurrence?.isCompleted == true { Label("完了", systemImage: "checkmark") }
                    }.font(.caption.bold()).foregroundStyle(DopaTheme.secondary)
                    if !task.details.isEmpty { Text(task.details).font(.subheadline).foregroundStyle(DopaTheme.secondary).lineLimit(2) }
                    if !task.labels.isEmpty {
                        Text(task.labels.map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundStyle(DopaTheme.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DopaTheme.secondary)
            }
        }
    }
}

func recurrenceLabel(_ recurrence: RecurrenceRule) -> String {
    switch recurrence.frequency {
    case .none: return "単発"
    case .daily: return "毎日"
    case .weekly:
        let names = ["日", "月", "火", "水", "木", "金", "土"]
        return recurrence.weekdays.sorted().filter { (1...7).contains($0) }.map { names[$0 - 1] }.joined(separator: "・") + "曜日"
    case .monthly: return "毎月\(recurrence.monthDay)日"
    }
}

func priorityLabel(_ priority: TaskPriority) -> String {
    switch priority { case .low: return "低"; case .normal: return "中"; case .high: return "高" }
}
