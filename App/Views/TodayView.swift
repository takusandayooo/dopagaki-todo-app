import SwiftUI
import DopagakiCore

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showEditor = false
    @State private var showFocus = false
    @State private var startingTask: TaskOccurrence?
    private var remaining: [TaskOccurrence] { store.today.filter { !$0.isCompleted } }
    private var completed: [TaskOccurrence] { store.today.filter(\.isCompleted) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    header
                    progressCard
                    if store.state.activeFocus != nil {
                        Button { showFocus = true } label: {
                            DopaCard(color: DopaTheme.blue.opacity(0.2)) {
                                HStack(spacing: 13) {
                                    Image(systemName: "timer").font(.title2).foregroundStyle(DopaTheme.green)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("集中セッションに戻る").font(.headline)
                                        Text(store.currentTask?.title ?? "計測中のタスク")
                                            .font(.subheadline).foregroundStyle(DopaTheme.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                            }
                        }.buttonStyle(.plain)
                    } else if let next = remaining.first(where: \.isMust) ?? remaining.first {
                        nextTask(next)
                    }
                    DopaSectionTitle(title: "今日のタスク", detail: "\(completed.count) / \(store.today.count) 完了")
                    if store.today.isEmpty {
                        DopaEmptyState(symbol: "sparkles", title: "今日の一歩を決めよう", message: "小さなタスクを1つ追加して、始めてみよう。")
                        Button { showEditor = true } label: { Label("タスクを追加", systemImage: "plus") }
                            .buttonStyle(DopaGlassButtonStyle())
                    } else {
                        VStack(spacing: 11) {
                            ForEach(remaining) { occurrence in
                                NavigationLink { TaskDetailView(occurrenceID: occurrence.id) } label: {
                                    TaskRow(occurrence: occurrence)
                                }
                                .buttonStyle(.plain)
                            }
                            if !completed.isEmpty {
                                Text("やりきったタスク").font(.caption.bold()).foregroundStyle(DopaTheme.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 7)
                                ForEach(completed) { occurrence in
                                    NavigationLink { TaskDetailView(occurrenceID: occurrence.id) } label: {
                                        TaskRow(occurrence: occurrence)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(20).padding(.bottom, 18)
            }
            .navigationTitle("今日")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditor = true } label: { Image(systemName: "plus").font(.title3.weight(.semibold)) }
                        .accessibilityLabel("新しいタスク")
                }
            }
            .sheet(isPresented: $showEditor) { TaskEditorView() }
            .sheet(isPresented: $showFocus) { FocusView() }
            .sheet(item: $startingTask) { task in
                FocusSetupView(occurrence: task) {
                    startingTask = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showFocus = true }
                }
            }
            .refreshable { store.refreshToday() }
            .onAppear { store.refreshToday() }
            .dopaPage()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date(), format: .dateTime.month().day().weekday(.wide))
                    .font(.subheadline.bold()).foregroundStyle(DopaTheme.secondary)
                Text(remaining.isEmpty && !store.today.isEmpty ? "今日も、やりきった！" : "小さな一歩が、力になる。")
                    .font(.system(.title2, design: .rounded, weight: .heavy))
            }
            Spacer(minLength: 5)
            VStack(spacing: 3) {
                Image(systemName: "flame.fill").foregroundStyle(.orange).font(.title2)
                Text("\(store.state.currentStreak(at: Date()))日").font(.caption.bold())
            }
        }
    }

    private var progressCard: some View {
        DopaCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TODAY'S MUST").font(.caption.bold()).tracking(1.5).foregroundStyle(DopaTheme.gold)
                        Text(store.totalMust == 0 ? "今日のマストを選ぼう" : store.mustRemaining == 0 ? "マストすべて達成！" : "あと\(store.mustRemaining)個でクリア")
                            .font(.title2.bold())
                    }
                    Spacer()
                    Image(systemName: store.totalMust > 0 && store.mustRemaining == 0 ? "checkmark.seal.fill" : "bolt.fill")
                        .font(.system(size: 36)).foregroundStyle(DopaTheme.gold)
                }
                if store.totalMust > 0 {
                    ProgressView(value: Double(store.totalMust - store.mustRemaining), total: Double(store.totalMust))
                        .tint(DopaTheme.gold)
                    Text("\(store.totalMust - store.mustRemaining) / \(store.totalMust) 完了")
                        .font(.caption.bold()).foregroundStyle(DopaTheme.secondary)
                } else {
                    Text("タスク詳細の「今日のマスト」をオンに。まずは1個で大丈夫。")
                        .font(.subheadline).foregroundStyle(DopaTheme.secondary)
                }
                Divider().overlay(DopaTheme.border)
                HStack {
                    Label("Lv.\(store.state.level)", systemImage: "star.fill").foregroundStyle(DopaTheme.gold).font(.headline)
                    ProgressView(value: store.state.levelProgress).tint(DopaTheme.blue)
                    Text("\(store.state.totalXP) XP").font(.caption.bold()).foregroundStyle(DopaTheme.secondary)
                }
                Label("あと\(store.state.xpToNextLevel) XPで Lv.\(store.state.level + 1)", systemImage: "sparkles")
                    .font(.subheadline.bold()).foregroundStyle(DopaTheme.gold)
                if store.mustRemaining == 1 {
                    Text("あと1個で、今日のマスト全達成！")
                        .font(.subheadline.bold()).foregroundStyle(DopaTheme.green)
                }
                HStack {
                    Label("今日の集中", systemImage: "clock")
                    Spacer()
                    Text(DopaTheme.duration(store.todaySeconds)).bold()
                }.font(.subheadline).foregroundStyle(DopaTheme.secondary)
            }
        }
    }

    private func nextTask(_ task: TaskOccurrence) -> some View {
        DopaCard(color: DopaTheme.blue.opacity(0.2)) {
            VStack(alignment: .leading, spacing: 17) {
                Text("次の一歩").font(.caption.bold()).foregroundStyle(DopaTheme.green)
                Text(task.title).font(.system(.title, design: .rounded, weight: .heavy))
                Button { startingTask = task } label: { Label("始める", systemImage: "play.fill") }
                    .buttonStyle(DopaGlassButtonStyle(color: DopaTheme.green, foreground: DopaTheme.background))
            }
        }
    }
}

struct FocusSetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let occurrence: TaskOccurrence
    var onStarted: () -> Void
    @State private var mode: FocusMode = .stopwatch
    @State private var hasTarget = false
    @State private var minutes = 25

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Text(occurrence.title).font(.largeTitle.bold())
                    Text("自分のペースで始めよう。目標はあとから延長できます。")
                        .foregroundStyle(DopaTheme.secondary)
                    Picker("計測方法", selection: $mode) {
                        Text("ストップウォッチ").tag(FocusMode.stopwatch)
                        Text("タイマー").tag(FocusMode.countdown)
                    }.pickerStyle(.segmented)
                    DopaCard {
                        VStack(spacing: 17) {
                            if mode == .stopwatch { Toggle("目標時間を決める", isOn: $hasTarget) }
                            if mode == .countdown || hasTarget {
                                Stepper("\(minutes)分", value: $minutes.selectionTick(.durationStep, level: store.state.settings.haptics), in: 1...360, step: 5)
                                    .font(.title3.bold())
                            }
                        }
                    }
                    Button {
                        store.startFocus(occurrence.id, mode: mode, targetMinutes: mode == .countdown || hasTarget ? minutes : nil)
                        if store.state.activeFocus?.occurrenceID == occurrence.id { onStarted(); dismiss() }
                    } label: { Label("集中を始める", systemImage: "play.fill") }
                        .buttonStyle(DopaGlassButtonStyle(color: DopaTheme.green, foreground: DopaTheme.background))
                }.padding(24)
            }
            .navigationTitle("計測を選ぶ").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
            .dopaPage()
            .onAppear {
                if let target = store.state.tasks.first(where: { $0.id == occurrence.taskID })?.targetMinutes {
                    hasTarget = true
                    minutes = max(1, min(360, target))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
