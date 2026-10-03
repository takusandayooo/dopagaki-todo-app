import SwiftUI
import FamilyControls
import DopagakiCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 15) {
                        Image(systemName: "star.fill").font(.system(size: 37)).foregroundStyle(DopaTheme.gold)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ドパギキ ToDo").font(.title2.bold())
                            Text("始めやすく。達成は、思いきり。")
                                .font(.caption).foregroundStyle(DopaTheme.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                Section {
                    Picker("触覚の強さ", selection: setting(\.haptics, tick: .checkOn)) {
                        Text("オフ").tag(HapticLevel.off)
                        Text("弱").tag(HapticLevel.soft)
                        Text("標準").tag(HapticLevel.standard)
                        Text("最大（100%）").tag(HapticLevel.strong)
                    }
                    NavigationLink {
                        HapticPreviewView()
                    } label: {
                        Label("振動を試す・\(HapticCue.allCases.count)パターン", systemImage: "waveform.path")
                    }
                    Toggle("達成の音", isOn: setting(\.soundEnabled))
                    Toggle("動きを減らす", isOn: setting(\.reduceMotion))
                } header: { Text("達成の演出") } footer: {
                    Text("星・メダルの動きを短くできます。iPhoneの「視差効果を減らす」も反映します。")
                }
                Section {
                    Toggle("やることを通知", isOn: setting(\.remindersEnabled))
                    if store.state.settings.remindersEnabled {
                        Picker("声をかける時刻", selection: setting(\.reminderHour, tick: .timeStep)) {
                            ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                        }
                        Stepper("1日の声かけ上限：\(store.state.settings.reminderDailyLimit)回", value: setting(\.reminderDailyLimit, tick: .durationStep), in: 1...4)
                        Button { Task { await store.requestNotifications() } } label: {
                            Label("通知の許可を確認", systemImage: "bell.badge")
                        }
                    }
                } header: { Text("リマインダー") } footer: {
                    Text("完了したタスクの催促は停止します。通知の表示はiPhoneの集中モードや通知設定によって変わります。")
                }
                Section("アプリの外でも確認") {
                    NavigationLink {
                        WidgetGuideView()
                    } label: {
                        Label("ウィジェット・Macで見る", systemImage: "rectangle.3.group")
                    }
                }
                #if DOPA_PERSONAL_TEAM
                Section("実機確認版") {
                    Text("このバージョンでは、Screen Timeによる他アプリの制限は利用できません。")
                        .font(.caption).foregroundStyle(DopaTheme.secondary)
                }
                #else
                ScreenTimeSettingsSection(service: store.screenTime)
                #endif
                Section {
                    LabeledContent("集計タイムゾーン", value: store.state.settings.aggregationTimeZoneID)
                    Text("活動の日付はこのタイムゾーンで集計します。端末の時差が変わっても、過去の草は移動しません。")
                        .font(.caption).foregroundStyle(DopaTheme.secondary)
                    LabeledContent("保存先", value: "このiPhone")
                    Text("タスク、集中時間、写真、メモを端末に保存します。")
                        .font(.caption).foregroundStyle(DopaTheme.secondary)
                } header: { Text("記録について") }
                Section {
                    Button { showPrivacy = true } label: {
                        Label("プライバシー", systemImage: "hand.raised.fill")
                    }
                    .accessibilityHint("保存するデータ、許可、削除について確認します")
                } header: { Text("このアプリについて") }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("設定")
            .dopaPage()
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacyExplanationView()
        }
    }

    private func setting<Value: Equatable>(_ path: WritableKeyPath<AppSettings, Value>, tick: HapticCue? = nil) -> Binding<Value> {
        Binding(get: { store.state.settings[keyPath: path] }, set: { value in
            guard store.state.settings[keyPath: path] != value else { return }
            var settings = store.state.settings
            settings[keyPath: path] = value
            store.updateSettings(settings)
            if let tick, store.state.settings[keyPath: path] == value {
                HapticsService.selection(tick, level: store.state.settings.haptics)
            }
        })
    }
}

private struct WidgetGuideView: View {
    var body: some View {
        Form {
            #if DOPA_PERSONAL_TEAM && !DOPA_WIDGETS
            Section {
                Text("この確認版にはウィジェットが含まれていません。ウィジェット対応版をインストールすると追加できます。")
            }
            #endif
            Section("ホーム画面") {
                Text("ホーム画面の空いている場所を長押しし、編集からウィジェットを追加。「ドパギキ」の「今日のマスト」を選びます。")
                Text("小サイズはマストの残り件数、中サイズはレベルと全タスクの残り件数も表示します。タップすると「今日」を開きます。")
            }
            Section("ロック画面") {
                Text("ロック画面を長押ししてカスタマイズし、ウィジェット欄から「ドパギキ」を選びます。円形・長方形・日付の上の表示に対応しています。")
                Text("タスク名やメモは表示しません。件数を見せたくない場合は、iPhoneのロック中のウィジェット表示設定を変更できます。")
            }
            Section("Macのデスクトップ") {
                Text("同じApple Accountを使うiPhoneのウィジェットをMacにも置けます。Macの「システム設定 → デスクトップとDock」でiPhoneウィジェットを有効にし、デスクトップを右クリックして追加します。")
                Text("macOS Sonoma 14以降が必要です。iPhoneを近くに置くか、同じWi-Fiに接続してください。")
            }
            Section("Macで通知を受け取る") {
                Text("Macの「iPhoneミラーリング」を設定して通知を許可し、「システム設定 → 通知 → iPhoneからの通知を許可」でドパギキを有効にします。")
                Text("iPhone側でも「やることを通知」をオンにしてください。通知には残り件数が表示されます。")
                Link("対応機種・設定をAppleの案内で確認", destination: URL(string: "https://support.apple.com/ja-jp/120421")!)
            }
            Section {
                Text("表示の更新や通知のタイミングはOSが調整します。最新の件数を確認したいときはアプリを開いてください。Macへの表示はiPhoneとの連係で、Mac単体でのタスク編集・データ同期には対応していません。")
            }
        }
        .navigationTitle("ウィジェットとMac")
        .scrollContentBackground(.hidden)
        .dopaPage()
    }
}

private struct PrivacyExplanationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("このバージョンで使うデータと許可について説明します。")
                        .foregroundStyle(DopaTheme.secondary)
                }
                Section("タスク・記録・写真") {
                    Text("タスク、集中時間、メモ、選んで添付した写真、達成結果は、このiPhoneに保存します。アカウント登録や、アプリ独自のクラウド同期はありません。運営者のサーバーへこれらを送信する機能や、広告・外部のアクセス解析はありません。")
                    Text("写真は選んだものだけを取り込みます。写真アプリの元画像を削除しても、このアプリへ保存したコピーは残ります。")
                }
                Section("話して記録する") {
                    Text("音声入力を使うときに、マイクと音声認識の許可を求めます。端末が対応している場合は端末内で認識し、対応していない場合はAppleのサービスへ音声を送信することがあります。")
                    Text("発話音声を録音ファイルとして保存しません。確認して保存した文字をメモとして残します。許可しなくても手入力を使えます。")
                }
                Section("Screen Time") {
                    #if DOPA_PERSONAL_TEAM
                    Text("この実機確認版では、Screen Timeによる他アプリの制限は利用できません。")
                    #else
                    Text("本人が許可し、選んだアプリなどをマスト達成まで制限します。選択内容を表す識別情報と、一時解除の日時を端末内に保存します。閲覧履歴や他アプリの詳細な使用時間を運営者へ送信する機能はありません。")
                    Text("アプリ内で制限をオフにでき、Screen Timeの許可はiPhoneの設定から取り消せます。")
                    #endif
                }
                Section("通知と許可の変更") {
                    Text("通知はiPhone内で予約します。通知にタスク名が表示されることがあります。通知、マイク、音声認識の許可や、ロック画面の通知プレビューはiPhoneの設定で変更できます。")
                }
                Section("TestFlightで利用する場合") {
                    Text("TestFlightでは、Appleがクラッシュログと使用状況情報を収集し、アプリの提供者に共有します。氏名・メールアドレスが含まれる場合があります。送信したコメントやスクリーンショットも共有され、不具合の調査や品質向上に使われることがあります。")
                    Link("AppleのTestFlightのプライバシー説明", destination: URL(string: "https://www.apple.com/legal/privacy/data/ja/test-flight/")!)
                }
                Section("削除とバックアップ") {
                    Text("アーカイブしても、過去の記録や添付写真は残ります。現在、全データの一括消去や、保存済みメモ・写真の個別削除を行う画面はありません。端末上のアプリデータの消去には、iOSのアプリ削除を使用してください。「Appを取り除く」ではデータが残ります。")
                    Text("iOSのバックアップに保存データが含まれる場合があります。アプリを削除しても、既存のバックアップやTestFlightで共有した情報がすべて同時に消去されることを意味しません。")
                }
            }
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .navigationTitle("プライバシー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .dopaPage()
        }
    }
}

private struct ScreenTimeSettingsSection: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var service: ScreenTimeService
    @State private var requesting = false
    @State private var showPicker = false
    @State private var draftSelection = FamilyActivitySelection()
    private var selectedCount: Int { service.selection.applicationTokens.count + service.selection.categoryTokens.count + service.selection.webDomainTokens.count }

    var body: some View {
        Section {
            HStack {
                Label("Screen Time", systemImage: "hourglass")
                Spacer()
                Text(service.isAuthorized ? "許可済み" : "未許可")
                    .font(.caption.bold()).foregroundStyle(service.isAuthorized ? DopaTheme.green : DopaTheme.secondary)
            }
            if !service.isAuthorized {
                Button {
                    requesting = true
                    Task { @MainActor in
                        await service.requestAuthorization()
                        requesting = false
                    }
                } label: {
                    Label(requesting ? "許可を確認中…" : "Screen Timeを許可", systemImage: "lock.shield")
                }.disabled(requesting)
            }
            Button {
                draftSelection = service.selection
                showPicker = true
            } label: {
                HStack {
                    Label("制限するアプリを選ぶ", systemImage: "app.badge")
                    Spacer()
                    Text(selectedCount == 0 ? "未選択" : "\(selectedCount)件")
                        .font(.caption).foregroundStyle(DopaTheme.secondary)
                }
            }.disabled(!service.isAuthorized)
            Toggle("マスト完了までアプリを制限", isOn: Binding(get: { service.isEnabled }, set: { service.setEnabled($0) }))
                .disabled(!service.isAuthorized)
            if service.isEnabled {
                Picker("翌日の再制限", selection: Binding(get: { service.resetHour }, set: { hour in
                    guard hour != service.resetHour else { return }
                    service.setResetHour(hour)
                    if service.resetHour == hour { HapticsService.selection(.timeStep, level: store.state.settings.haptics) }
                })) {
                    ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                }
                if store.totalMust == 0 {
                    Label("今日はマストがないため制限しません", systemImage: "lock.open")
                        .font(.caption).foregroundStyle(DopaTheme.secondary)
                } else if store.mustRemaining == 0 {
                    Label("マスト達成！次の再制限まで解放", systemImage: "checkmark.shield.fill")
                        .font(.caption.bold()).foregroundStyle(DopaTheme.green)
                } else {
                    Text("今日のマストはあと\(store.mustRemaining)個。すべて完了で解放します。")
                        .font(.caption).foregroundStyle(DopaTheme.secondary)
                }
                if let until = service.temporaryUnlockUntil {
                    HStack {
                        Label("一時解除中", systemImage: "lock.open.fill")
                        Spacer()
                        Text(until, format: .dateTime.hour().minute())
                    }.font(.caption).foregroundStyle(DopaTheme.gold)
                }
                Button { service.temporarilyUnlock(minutes: 15) } label: {
                    Label("15分だけ一時解除", systemImage: "lock.open")
                }
                Button { service.restoreRestrictions() } label: {
                    Label("制限の状態を更新", systemImage: "arrow.clockwise")
                }
            }
            if let message = service.lastError {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            if !service.unlockHistory.isEmpty {
                DisclosureGroup("一時解除の履歴") {
                    ForEach(Array(service.unlockHistory.sorted(by: >).enumerated()), id: \.offset) { _, date in
                        Label(date.formatted(.dateTime.year().month().day().hour().minute()), systemImage: "lock.open")
                            .font(.caption).foregroundStyle(DopaTheme.secondary)
                    }
                }
            }
        } header: { Text("マストとアプリ制限") } footer: {
            Text("選んだアプリを今日のマスト達成まで制限します。必要なときは一時解除できます。Screen Timeの許可はiPhoneの設定から取り消せます。")
        }
        .onAppear { service.refreshAuthorization() }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                FamilyActivityPicker(selection: $draftSelection)
                    .navigationTitle("制限するアプリ")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { showPicker = false } }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("保存") { service.updateSelection(draftSelection); showPicker = false }.bold()
                        }
                    }
                    .dopaPage()
            }
        }
    }
}

private struct HapticPreviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: HapticCue?
    @State private var previewID = UUID()
    private let groups = ["日付・時間を選ぶ", "いつもの操作", "集中タイマー", "達成のお祝い"]

    var body: some View {
        Form {
            Section {
                Picker("触覚の強さ", selection: Binding(get: { store.state.settings.haptics }, set: { value in
                    guard value != store.state.settings.haptics else { return }
                    stopPreview()
                    var settings = store.state.settings
                    settings.haptics = value
                    store.updateSettings(settings)
                    if store.state.settings.haptics == value {
                        HapticsService.play(.checkOn, level: value)
                    }
                })) {
                    Text("オフ").tag(HapticLevel.off)
                    Text("弱").tag(HapticLevel.soft)
                    Text("標準").tag(HapticLevel.standard)
                    Text("最大").tag(HapticLevel.strong)
                }
                .pickerStyle(.segmented)
                Text(store.state.settings.haptics == .off ? "強さを選ぶと、振動を試せます。" : "気になる場面をタップ。アプリで使う振動をそのまま試せます。")
                    .font(.subheadline).foregroundStyle(DopaTheme.secondary)
            } footer: {
                Text("「最大」はすべての振動をAPI上限の100%で再生します。ここで選んだ強さはアプリ全体に反映されます。音は鳴りません。")
            }
            ForEach(groups, id: \.self) { group in
                Section(group) {
                    ForEach(HapticCue.allCases.filter { $0.group == group }) { cue in
                        Button {
                            selected = cue
                            previewID = UUID()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(cue.title).font(.headline).foregroundStyle(.white)
                                    Text(cue.rhythm).font(.caption).foregroundStyle(DopaTheme.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: selected == cue ? "waveform" : "hand.tap")
                                    .foregroundStyle(selected == cue ? DopaTheme.gold : DopaTheme.green)
                                    .accessibilityHidden(true)
                            }.padding(.vertical, 4)
                        }
                        .disabled(store.state.settings.haptics == .off)
                        .accessibilityLabel("\(cue.title)、\(cue.rhythm)")
                        .accessibilityHint("振動を試します")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("振動を試す")
        .navigationBarTitleDisplayMode(.inline)
        .dopaPage()
        .task(id: previewID) {
            guard let cue = selected, scenePhase == .active else { return }
            HapticsService.stop()
            HapticsService.play(cue, level: store.state.settings.haptics)
            do { try await Task.sleep(for: .milliseconds(Int((HapticsService.duration(for: cue) + 0.15) * 1_000))) }
            catch { return }
            guard !Task.isCancelled else { return }
            selected = nil
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopPreview() } }
        .onDisappear { stopPreview() }
    }

    private func stopPreview() {
        selected = nil
        previewID = UUID()
        HapticsService.stop()
    }
}
