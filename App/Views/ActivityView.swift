import SwiftUI
import DopagakiCore

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var periodEnd = Date()
    @State private var selectedDate = Date()
    @State private var selectedMedal: MedalKind?
    private var days: [DayActivity] { store.state.activityDays(ending: periodEnd, weeks: 13) }
    private var day: DayActivity { store.state.activity(on: selectedDate) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("一歩ずつ、積み重なってる。").font(.title2.bold())
                        Text("取り組んだ時間も、終えたタスクも、ここに。")
                            .font(.subheadline).foregroundStyle(DopaTheme.secondary)
                    }
                    HStack(spacing: 12) {
                        DopaMetric(symbol: "flame.fill", value: "\(store.state.currentStreak(at: Date()))日", label: "いまの連続記録", accent: .orange)
                        DopaMetric(symbol: "clock.fill", value: DopaTheme.duration(store.state.totalSeconds), label: "累計集中時間")
                    }
                    calendarCard
                    dailyDetail
                    HStack {
                        DopaSectionTitle(title: "メダルコレクション", detail: "\(store.state.medals.count) / \(MedalKind.allCases.count)")
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 15) {
                        ForEach(MedalKind.allCases) { medal in
                            Button { selectedMedal = medal } label: {
                                VStack(spacing: 12) {
                                    MedalBadge(kind: medal, earned: store.state.medals.contains { $0.id == medal })
                                        .frame(width: 77, height: 90)
                                    Text(medal.title).font(.caption.bold()).foregroundStyle(.white).lineLimit(2).frame(minHeight: 28)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(DopaTheme.surface, in: RoundedRectangle(cornerRadius: 21))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(medal.title)、\(store.state.medals.contains { $0.id == medal } ? "獲得済み" : "未獲得")。条件を確認")
                        }
                    }
                    HStack {
                        Label("最長連続 \(store.state.longestStreak())日", systemImage: "flag.checkered")
                        Spacer()
                        Text("Lv.\(store.state.level) · \(store.state.totalXP) XP")
                    }.font(.caption.bold()).foregroundStyle(DopaTheme.secondary)
                }.padding(20).padding(.bottom, 20)
            }
            .navigationTitle("記録・実績")
            .sheet(item: $selectedMedal) { medal in
                medalDetail(medal)
            }
            .dopaPage()
            .environment(\.calendar, store.state.calendar)
            .environment(\.timeZone, store.state.calendar.timeZone)
        }
    }

    private var calendarCard: some View {
        DopaCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("活動カレンダー").font(.headline)
                    Spacer()
                    Button { movePeriod(-91) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 44) }
                        .accessibilityLabel("前の3か月")
                    Button { movePeriod(91) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 44) }
                        .disabled(store.state.calendar.isDate(periodEnd, inSameDayAs: Date()))
                        .accessibilityLabel("次の3か月")
                }
                if let first = days.first, let last = days.last {
                    Text("\(first.date.formatted(.dateTime.month().day())) 〜 \(last.date.formatted(.dateTime.year().month().day()))")
                        .font(.caption).foregroundStyle(DopaTheme.secondary)
                }
                GeometryReader { geometry in
                    let width = max(9, (geometry.size.width - 25 - 12 * 4) / 13)
                    HStack(alignment: .top, spacing: 6) {
                        VStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { row in
                                Text(["日", "", "火", "", "木", "", "土"][row])
                                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(DopaTheme.secondary)
                                    .frame(width: 19, height: width)
                            }
                        }
                        HStack(alignment: .top, spacing: 4) {
                            ForEach(0..<13, id: \.self) { week in
                                VStack(spacing: 4) {
                                    ForEach(0..<7, id: \.self) { weekday in
                                        let index = week * 7 + weekday
                                        if index < days.count {
                                            let item = days[index]
                                            Button {
                                                guard !store.state.calendar.isDate(item.date, inSameDayAs: selectedDate) else { return }
                                                selectedDate = item.date
                                                HapticsService.selection(.dateStep, level: store.state.settings.haptics)
                                            } label: {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(DopaTheme.grass[min(4, max(0, item.intensity))])
                                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(store.state.calendar.isDate(item.date, inSameDayAs: selectedDate) ? .white : .clear, lineWidth: 2))
                                                    .frame(width: width, height: width)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("\(item.date.formatted(date: .long, time: .omitted))、集中\(DopaTheme.duration(item.seconds))、\(item.completedCount)件完了")
                                            .accessibilityHint("この日の記録を表示")
                                        } else { Color.clear.frame(width: width, height: width).accessibilityHidden(true) }
                                    }
                                }
                            }
                        }
                    }
                }.frame(height: max(90, min(190, 7 * 23 + 24)))
                HStack(spacing: 5) {
                    Text("少ない")
                    ForEach(0..<5, id: \.self) { value in RoundedRectangle(cornerRadius: 3).fill(DopaTheme.grass[value]).frame(width: 12, height: 12) }
                    Text("多い")
                    Spacer()
                    Text("集中時間")
                }.font(.system(size: 10, weight: .semibold)).foregroundStyle(DopaTheme.secondary)
                DatePicker("日付を選ぶ", selection: $selectedDate.dateSelectionTick(calendar: store.state.calendar, includesTime: false, level: store.state.settings.haptics), in: ...Date(), displayedComponents: .date)
                    .font(.subheadline)
                Text("計測なしのタスク完了も、一歩として草に残ります。")
                    .font(.caption).foregroundStyle(DopaTheme.secondary)
            }
        }
    }

    private var dailyDetail: some View {
        DopaCard {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text(selectedDate, format: .dateTime.month().day().weekday()) .font(.headline)
                    Spacer()
                    Text("\(day.completedCount)件完了").font(.caption.bold()).foregroundStyle(DopaTheme.green)
                }
                Text(DopaTheme.duration(day.seconds)).font(.title.bold())
                if !day.isActive && dayNotes.isEmpty {
                    Text("この日の記録はありません。次の一歩は、いつからでも。")
                        .font(.subheadline).foregroundStyle(DopaTheme.secondary)
                }
                ForEach(daySessions) { session in
                    HStack(spacing: 11) {
                        Image(systemName: "timer").foregroundStyle(DopaTheme.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.taskTitle).font(.subheadline.bold())
                            Text(DopaTheme.duration(secondsInDay(session))).font(.caption).foregroundStyle(DopaTheme.secondary)
                        }
                    }
                }
                ForEach(dayCompletions) { occurrence in
                    NavigationLink { TaskDetailView(occurrenceID: occurrence.id) } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(DopaTheme.green)
                            Text(occurrence.title).font(.subheadline.bold())
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }.foregroundStyle(.white)
                    }.buttonStyle(.plain)
                }
                ForEach(dayNotes) { note in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(note.createdAt, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(DopaTheme.secondary)
                        if !note.text.isEmpty { Text(note.text).font(.subheadline) }
                        StoredPhotos(names: note.photoNames)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DopaTheme.elevated, in: RoundedRectangle(cornerRadius: 15))
                }
                ForEach(dayMedals) { medal in
                    Label("\(medal.id.title)を獲得", systemImage: "medal.fill")
                        .font(.subheadline.bold()).foregroundStyle(DopaTheme.gold)
                }
            }
        }
    }

    private var daySessions: [FocusSession] { store.state.sessions.filter { secondsInDay($0) > 0 }.sorted { $0.startedAt < $1.startedAt } }
    private var dayNotes: [ActivityNote] { store.state.notes.filter { store.state.calendar.isDate($0.createdAt, inSameDayAs: selectedDate) }.sorted { $0.createdAt < $1.createdAt } }
    private var dayCompletions: [TaskOccurrence] { store.state.occurrences.filter { $0.completedAt.map { store.state.calendar.isDate($0, inSameDayAs: selectedDate) } ?? false } }
    private var dayMedals: [EarnedMedal] { store.state.medals.filter { store.state.calendar.isDate($0.earnedAt, inSameDayAs: selectedDate) } }

    private func secondsInDay(_ session: FocusSession) -> Double {
        let start = store.state.calendar.startOfDay(for: selectedDate)
        let end = store.state.calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return session.segments.reduce(0) { sum, segment in sum + max(0, min(end, segment.end).timeIntervalSince(max(start, segment.start))) }
    }

    private func movePeriod(_ offset: Int) {
        periodEnd = min(Date(), store.state.calendar.date(byAdding: .day, value: offset, to: periodEnd) ?? periodEnd)
        selectedDate = periodEnd
    }

    private func medalDetail(_ medal: MedalKind) -> some View {
        let earned = store.state.medals.first { $0.id == medal }
        return NavigationStack {
            VStack(spacing: 22) {
                MedalBadge(kind: medal, earned: earned != nil).frame(width: 170, height: 195)
                Text(medal.title).font(.largeTitle.bold())
                Text(medal.condition).font(.headline).foregroundStyle(DopaTheme.secondary)
                if let earned {
                    Label("獲得済み", systemImage: "checkmark.seal.fill").foregroundStyle(DopaTheme.gold)
                    Text(earned.earnedAt, format: .dateTime.year().month().day()).font(.subheadline).foregroundStyle(DopaTheme.secondary)
                } else {
                    Text("これからの楽しみに。").foregroundStyle(DopaTheme.secondary)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(25)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { selectedMedal = nil } } }
                .dopaPage()
        }.presentationDetents([.medium, .large])
    }
}

struct MedalBadge: View {
    let kind: MedalKind
    let earned: Bool

    private var assetName: String {
        switch kind {
        case .firstStep: "MedalFirstStep"
        case .weekStreak: "MedalWeekStreak"
        case .monthStreak: "MedalMonthStreak"
        case .tenHours: "MedalTenHours"
        case .hundredHours: "MedalHundredHours"
        case .comeback: "MedalComeback"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            Image(assetName)
                .resizable()
                .scaledToFit()
                .saturation(earned ? 1 : 0)
                .opacity(earned ? 1 : 0.42)
                .frame(width: size, height: size)
                .shadow(color: earned ? DopaTheme.gold.opacity(0.16) : .clear, radius: 10)
                .overlay(alignment: .bottomTrailing) {
                    if !earned {
                        Image(systemName: "lock.fill")
                            .font(.system(size: min(20, size * 0.16), weight: .bold))
                            .foregroundStyle(DopaTheme.secondary)
                            .padding(size * 0.055)
                            .background(DopaTheme.surface, in: Circle())
                            .padding(size * 0.06)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityHidden(true)
    }
}
