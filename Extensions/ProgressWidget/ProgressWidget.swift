import SwiftUI
import WidgetKit
import DopagakiCore

struct ProgressEntry: TimelineEntry {
    let date: Date
    let progress: WidgetDayProgress?

    static func example(at now: Date) -> Self {
        var state = AppState()
        for title in ["読書", "勉強", "片づけ"] {
            state.saveTask(TaskDefinition(title: title, createdAt: now, isMust: true), on: now)
        }
        if let first = state.occurrences.first { state.complete(occurrenceID: first.id, at: now) }
        return Self(date: now, progress: WidgetDayProgress(state: state, on: now))
    }
}

struct ProgressProvider: TimelineProvider {
    private func snapshot() -> WidgetProgressSnapshot? {
        #if os(watchOS)
        return (try? WatchProgressRepository().load())?.snapshot
        #else
        return try? WidgetSnapshotRepository().load()
        #endif
    }
    func placeholder(in context: Context) -> ProgressEntry { .example(at: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        let now = Date()
        if context.isPreview { completion(.example(at: now)); return }
        let snapshot = snapshot()
        completion(ProgressEntry(date: now, progress: snapshot?.progress(at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let now = Date()
        let snapshot = snapshot()
        var entries = [ProgressEntry(date: now, progress: snapshot?.progress(at: now))]
        // Upcoming day entries reset recurring musts even without opening the app.
        if let snapshot {
            entries += snapshot.days.filter { $0.date > now }.map { ProgressEntry(date: $0.date, progress: $0) }
            if let expiration = snapshot.days.last?.validUntil, expiration > now {
                entries.append(ProgressEntry(date: expiration, progress: nil))
            }
        }
        // Refresh requests are subject to the OS budget; never promise instant updates.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

struct ProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: ProgressEntry
    private let gold = Color(red: 1, green: 0.77, blue: 0.22)
    private var ink: Color { renderingMode == .fullColor ? .white : .primary }

    var body: some View {
        Group {
            if let progress = entry.progress {
                switch family {
                case .accessoryInline:
                    Label(progress.headline, systemImage: progress.mustComplete ? "checkmark.seal.fill" : "bolt.fill")
                case .accessoryCircular:
                    ring(progress)
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 3) {
                        #if os(watchOS)
                        Label("マスト · Lv.\(progress.level)", systemImage: "bolt.fill").font(.caption)
                        #else
                        Label("今日のマスト", systemImage: "bolt.fill").font(.caption)
                        #endif
                        Text(progress.headline).font(.headline).minimumScaleFactor(0.65)
                        ProgressView(value: progress.progress)
                    }
                #if os(watchOS)
                case .accessoryCorner:
                    Text(progress.mustComplete ? "✓" : progress.mustTotal == 0 ? "—" : "\(progress.mustRemaining)")
                        .font(.title.bold())
                        .widgetLabel { Text(progress.headline) }
                #endif
                default:
                    #if os(watchOS)
                    ring(progress)
                    #else
                    home(progress)
                    #endif
                }
            } else {
                if family == .accessoryCircular {
                    Image(systemName: "arrow.clockwise").accessibilityLabel("ドパギキを開いて更新")
                } else if family == .accessoryInline {
                    Label("ドパギキを開いて更新", systemImage: "arrow.clockwise")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "bolt.fill").widgetAccentable()
                        Text("アプリを開いて更新").font(.caption.bold())
                        #if os(iOS)
                        if family == .systemSmall || family == .systemMedium {
                            Text("今日のマストをここに").font(.caption2)
                        }
                        #endif
                    }
                    #if os(iOS)
                    .foregroundStyle(family == .systemSmall || family == .systemMedium ? ink : .primary)
                    #endif
                }
            }
        }
        .privacySensitive()
        #if os(iOS)
        .widgetURL(URL(string: "\(Bundle.main.object(forInfoDictionaryKey: "DopaURLScheme") as? String ?? "dopagaki")://today"))
        #endif
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.07, green: 0.20, blue: 0.40), Color(red: 0.03, green: 0.05, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func ring(_ progress: WidgetDayProgress) -> some View {
        Gauge(value: progress.progress) {
            Image(systemName: "bolt.fill")
        } currentValueLabel: {
            if progress.mustComplete { Image(systemName: "checkmark") }
            else if progress.mustTotal == 0 { Text("—") }
            else { Text("\(progress.mustRemaining)").monospacedDigit() }
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.headline)
    }

    #if os(iOS)
    private func home(_ progress: WidgetDayProgress) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label("今日のマスト", systemImage: "bolt.fill")
                    .font(.caption.bold()).foregroundStyle(gold).widgetAccentable()
                Spacer(minLength: 0)
                if progress.mustComplete {
                    Text("全達成！").font(.system(.largeTitle, design: .rounded, weight: .heavy))
                } else if progress.mustTotal == 0 {
                    Text("マストなし").font(.title2.bold())
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("あと").font(.caption.bold())
                        Text("\(progress.mustRemaining)").font(.system(size: 48, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text("個").font(.headline)
                    }
                }
                ProgressView(value: progress.progress).tint(gold)
                Text(progress.mustTotal == 0 ? "今日の一歩を決めよう" : "\(progress.mustCompleted) / \(progress.mustTotal) 個 達成")
                    .font(.caption2).opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 10) {
                    Label("LEVEL \(progress.level)", systemImage: "star.fill")
                        .font(.headline).foregroundStyle(gold).widgetAccentable()
                    Text("次のレベルまで\n\(progress.xpToNextLevel) XP").font(.caption).lineLimit(2)
                    Divider().overlay(ink.opacity(0.2))
                    Text("全タスク あと\(progress.taskRemaining)個").font(.caption.bold())
                    Text("タップして取り組む").font(.caption2).opacity(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(ink)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .accessibilityElement(children: .combine)
    }
    #endif
}

@main
struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotRepository.kind, provider: ProgressProvider()) { entry in
            ProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("今日のマスト")
        .description("あと何個で達成？ 今日のマストとレベルをひと目で。")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

#if os(iOS)
#Preview(as: .systemSmall) {
    ProgressWidget()
} timeline: {
    ProgressEntry.example(at: Date())
}

#Preview(as: .systemMedium) {
    ProgressWidget()
} timeline: {
    ProgressEntry.example(at: Date())
}
#else
#Preview(as: .accessoryRectangular) {
    ProgressWidget()
} timeline: {
    ProgressEntry.example(at: Date())
}
#endif
