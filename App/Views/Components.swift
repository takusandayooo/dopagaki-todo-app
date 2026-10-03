import SwiftUI
import PhotosUI
import UIKit
import DopagakiCore

struct TaskRow: View {
    @EnvironmentObject private var store: AppStore
    let occurrence: TaskOccurrence
    var showMust = true
    private var definition: TaskDefinition? { store.state.tasks.first { $0.id == occurrence.taskID } }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: occurrence.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(occurrence.isCompleted ? DopaTheme.green : DopaTheme.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(occurrence.title)
                    .font(.headline)
                    .strikethrough(occurrence.isCompleted)
                    .foregroundStyle(occurrence.isCompleted ? DopaTheme.secondary : .white)
                HStack(spacing: 7) {
                    if showMust && occurrence.isMust {
                        Label("マスト", systemImage: "bolt.fill").foregroundStyle(DopaTheme.gold)
                    }
                    if let definition { Text(definition.listName).foregroundStyle(DopaTheme.secondary) }
                    if let deadline = occurrence.deadline {
                        Text(deadline, format: .dateTime.month().day())
                            .foregroundStyle(deadline < Date() && !occurrence.isCompleted ? Color.orange : DopaTheme.secondary)
                    }
                }
                .font(.caption.bold())
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DopaTheme.secondary)
        }
        .padding(16)
        .background(DopaTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(occurrence.title)、\(occurrence.isCompleted ? "完了" : "未完了")\(occurrence.isMust ? "、今日のマスト" : "")")
    }
}

struct StoredPhotos: View {
    @EnvironmentObject private var store: AppStore
    let names: [String]
    @State private var selectedImage: UIImage?

    var body: some View {
        if !names.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(names, id: \.self) { name in
                        if let url = store.photoURL(name), let image = UIImage(contentsOfFile: url.path) {
                            Button { selectedImage = image } label: {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 92, height: 92).clipShape(RoundedRectangle(cornerRadius: 15))
                            }
                            .accessibilityLabel("添付写真を拡大")
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { selectedImage != nil }, set: { if !$0 { selectedImage = nil } })) {
                NavigationStack {
                    Group {
                        if let selectedImage { Image(uiImage: selectedImage).resizable().scaledToFit() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DopaTheme.background)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { selectedImage = nil } } }
                    .dopaPage()
                }
            }
        }
    }
}

struct NewPhotosPicker: View {
    @Binding var photos: [Data]
    @State private var selections: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(selection: $selections, maxSelectionCount: 6, matching: .images) {
                Label(isLoading ? "写真を読み込み中…" : "写真を追加", systemImage: "photo.badge.plus")
                    .font(.subheadline.bold()).padding(.vertical, 9)
            }
            .disabled(isLoading)
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 13))
                                    .overlay(alignment: .topTrailing) {
                                        Button { photos.remove(at: index) } label: {
                                            Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, DopaTheme.background).font(.title3)
                                        }
                                        .accessibilityLabel("写真を削除")
                                    }
                            }
                        }
                    }
                }
            }
            if let loadError { Text(loadError).font(.caption).foregroundStyle(.orange) }
        }
        .onChange(of: selections) { _, items in
            Task { @MainActor in
                isLoading = true
                loadError = nil
                var loaded: [Data] = []
                for item in items {
                    do {
                        if let data = try await item.loadTransferable(type: Data.self) { loaded.append(data) }
                    } catch { loadError = "読み込めない写真がありました。もう一度選択してください。" }
                }
                photos = loaded
                isLoading = false
            }
        }
        .onChange(of: photos.count) { _, count in
            if count == 0 && !isLoading { selections = [] }
        }
    }
}

struct VoiceTextInput: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var text: String
    var placeholder = "何をやりましたか？"
    var multiline = true
    @StateObject private var recorder = SpeechRecorder()
    @State private var baseline = ""
    @State private var lastAppliedText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if multiline {
                TextField(placeholder, text: $text, axis: .vertical).lineLimit(3...8)
                    .padding(14).background(DopaTheme.elevated, in: RoundedRectangle(cornerRadius: 15))
            } else {
                TextField(placeholder, text: $text)
            }
            Button {
                if recorder.isRecording { recorder.stop() }
                else {
                    baseline = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    lastAppliedText = text
                    recorder.transcript = ""
                    Task { await recorder.start() }
                }
            } label: {
                Label(recorder.isRecording ? "録音を止める" : "話して入力", systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
            }
            .buttonStyle(DopaButtonStyle(color: recorder.isRecording ? .red : DopaTheme.elevated))
            if recorder.isRecording {
                Label("聞いています。終わったら停止を押してください。", systemImage: "waveform")
                    .font(.caption).foregroundStyle(DopaTheme.green)
            }
            if let error = recorder.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .onChange(of: recorder.transcript) { _, value in
            guard !value.isEmpty else { return }
            // Preserve manual corrections made while a final recognition result arrives.
            guard text == lastAppliedText else { return }
            text = baseline.isEmpty ? value : baseline + "\n" + value
            lastAppliedText = text
        }
        .onDisappear { recorder.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { recorder.stop() }
        }
    }
}

struct NoteComposer: View {
    @EnvironmentObject private var store: AppStore
    let occurrenceID: UUID
    @State private var text = ""
    @State private var photos: [Data] = []
    @State private var saved = false
    @State private var composerGeneration = UUID()

    var body: some View {
        DopaCard {
            VStack(alignment: .leading, spacing: 17) {
                Text("今日のひとこと").font(.headline)
                Text("話した内容を確認して、そのまま記録。メモなしでも大丈夫。")
                    .font(.subheadline).foregroundStyle(DopaTheme.secondary)
                VoiceTextInput(text: $text).id(composerGeneration)
                NewPhotosPicker(photos: $photos)
                Button {
                    store.saveNote(occurrenceID: occurrenceID, text: text, photos: photos)
                    if store.lastError == nil {
                        text = ""
                        photos = []
                        saved = true
                        composerGeneration = UUID()
                    }
                } label: { Label("記録を保存", systemImage: "square.and.arrow.down") }
                    .buttonStyle(DopaButtonStyle(color: DopaTheme.green, foreground: DopaTheme.background))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photos.isEmpty)
                if saved { Label("記録を保存しました", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(DopaTheme.green) }
                if let error = store.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }
        .onChange(of: text) { _, _ in saved = false }
    }
}

// Wrap the control's setter so restoration/onAppear does not create phantom ticks.
// This feedback acknowledges a selection, independently of the later Save action.
extension Binding where Value: Equatable {
    @MainActor
    func selectionTick(_ cue: HapticCue, level: HapticLevel) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { value in
            guard value != wrappedValue else { return }
            wrappedValue = value
            HapticsService.selection(cue, level: level)
        })
    }
}

extension Binding where Value == Date {
    @MainActor
    func dateSelectionTick(calendar: Calendar, includesTime: Bool = true, level: HapticLevel) -> Binding<Date> {
        Binding(get: { wrappedValue }, set: { value in
            let old = wrappedValue
            guard value != old else { return }
            wrappedValue = value
            if !calendar.isDate(old, inSameDayAs: value) {
                HapticsService.selection(.dateStep, level: level)
            } else if includesTime,
                      calendar.dateComponents([.hour, .minute], from: old) != calendar.dateComponents([.hour, .minute], from: value) {
                HapticsService.selection(.timeStep, level: level)
            }
        })
    }
}
