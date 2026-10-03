import SwiftUI
import DopagakiCore

struct FocusView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var reachedTarget = false
    @State private var isFinishing = false

    var body: some View {
        NavigationStack {
            Group {
                if let focus = store.state.activeFocus {
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        let elapsed = focus.elapsed(at: context.date)
                        focusContent(focus, elapsed: elapsed)
                            .onChange(of: context.date) { _, date in
                                guard focus.mode == .countdown, let target = focus.targetSeconds, focus.elapsed(at: date) >= target, !focus.isPaused, !isFinishing else { return }
                                if store.pauseFocus(reachedTarget: true) { reachedTarget = true }
                            }
                    }
                } else {
                    DopaEmptyState(symbol: "checkmark.circle", title: "記録を保存しました", message: "取り組んだ時間は、記録・実績に残っています。")
                }
            }
            .navigationTitle("集中する").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("戻る") { dismiss() }.disabled(isFinishing)
                        .accessibilityHint("計測を続けたまま今日の画面に戻ります")
                }
            }
            .alert("目標時間に到達！", isPresented: $reachedTarget) {
                Button("5分延長") { extend(5) }
                Button("15分延長") { extend(15) }
                Button("ここで区切る", role: .cancel) { }
            } message: { Text("おつかれさま。計測を一時停止しました。時間だけ保存するか、タスクを完了するか選べます。") }
            .dopaPage()
        }
    }

    private func focusContent(_ focus: ActiveFocus, elapsed: Double) -> some View {
        let target = focus.targetSeconds
        let shown = focus.mode == .countdown ? max(0, (target ?? 0) - elapsed) : elapsed
        let progress = target.map { min(1, elapsed / max(1, $0)) } ?? 0
        return ScrollView {
            VStack(spacing: 30) {
                VStack(spacing: 10) {
                    Text(focus.mode == .stopwatch ? "STOPWATCH" : "TIMER")
                        .font(.caption.bold()).tracking(2).foregroundStyle(DopaTheme.green)
                    Text(store.currentTask?.title ?? "集中中のタスク").font(.title.bold()).multilineTextAlignment(.center)
                    Label(focus.isPaused ? "ひと休み中" : "あなたのペースで、続けよう。", systemImage: focus.isPaused ? "pause.circle" : "sparkle")
                        .font(.subheadline).foregroundStyle(DopaTheme.secondary)
                }
                ZStack {
                    Circle().stroke(DopaTheme.elevated, lineWidth: 13)
                    Circle().trim(from: 0, to: target == nil ? 1 : progress)
                        .stroke(DopaTheme.green.opacity(target == nil ? 0.6 : 1), style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 12) {
                        Text(DopaTheme.clock(shown))
                            .font(.system(size: elapsed >= 3600 ? 46 : 60, weight: .heavy, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        Text(focus.mode == .countdown ? "残り時間" : "経過時間").font(.caption.bold()).foregroundStyle(DopaTheme.secondary)
                        if let target {
                            Text("目標 \(DopaTheme.duration(target))").font(.subheadline.bold()).foregroundStyle(DopaTheme.green)
                        }
                    }.padding(25)
                }
                .frame(maxWidth: 290).aspectRatio(1, contentMode: .fit).padding(.horizontal, 18)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(focus.mode == .countdown ? "残り" : "経過")\(DopaTheme.duration(shown))、\(focus.isPaused ? "一時停止中" : "計測中")")
                VStack(spacing: 17) {
                    Button {
                        if focus.isPaused { store.resumeFocus() } else { store.pauseFocus() }
                    } label: {
                        Label(focus.mode == .countdown && focus.isPaused && shown <= 0 ? "延長して再開しよう" : focus.isPaused ? "再開する" : "一時停止", systemImage: focus.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(DopaGlassButtonStyle(color: DopaTheme.elevated, prominent: false))
                    .disabled(focus.mode == .countdown && focus.isPaused && shown <= 0)
                    if target != nil {
                        HStack(spacing: 13) {
                            Button { extend(5) } label: { Text("＋5分") }
                            Button { extend(15) } label: { Text("＋15分") }
                        }.buttonStyle(DopaGlassButtonStyle(color: DopaTheme.surface, prominent: false))
                    }
                    Divider().padding(.vertical, 5)
                    Button { finish(complete: true) } label: { Label("タスクを完了", systemImage: "checkmark") }
                        .buttonStyle(DopaGlassButtonStyle(color: DopaTheme.green, foreground: DopaTheme.background))
                    Button { finish(complete: false) } label: { Label("時間だけ保存して終了", systemImage: "square.and.arrow.down") }
                        .buttonStyle(DopaGlassButtonStyle(color: DopaTheme.surface, prominent: false))
                    Text("ここまでの時間はどちらでも保存されます。\n勉強の続きがあるときは、時間だけ保存。")
                        .font(.caption).foregroundStyle(DopaTheme.secondary).multilineTextAlignment(.center)
                    if let error = store.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
                }.disabled(isFinishing)
            }.padding(25)
        }
    }

    private func extend(_ minutes: Int) {
        store.extendFocus(minutes: minutes, resumeIfPaused: true)
    }

    private func finish(complete: Bool) {
        guard !isFinishing else { return }
        isFinishing = true
        // Persist before dismissing; only the root's reward presentation is delayed.
        store.finishFocus(completeTask: complete)
        if store.lastError == nil { dismiss() }
        else { isFinishing = false }
    }
}
