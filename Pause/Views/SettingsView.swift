import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.invalid("This file couldn’t be read.") }; self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingImport: Data?
    @State private var importSummary = ""
    @State private var importConfirmation = false
    @State private var message: String?
    @State private var permission: AppModel.PermissionPurpose?
    private var reminderDate: Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(hour: model.preferences.reminderHour, minute: model.preferences.reminderMinute)) ?? Date() }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.updatePreferences { $0.reminderHour = c.hour ?? 20; $0.reminderMinute = c.minute ?? 0 }
            Task { await model.updateReminder() }
        })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(model.dailyGoal) minutes a day", value: Binding(get: { model.dailyGoal }, set: model.setGoal), in: 1...180)
                } header: { PauseSectionHeader(title: "Your daily intention") } footer: { PauseSectionFooter(text: "Your current goal is used to count every day in your calendar, including days in the past.") }
                    .listRowBackground(Palette.paper).listRowSeparatorTint(Palette.line.opacity(0.55))
                Section {
                    NavigationLink("Sounds & bells") { SoundSettingsView() }
                    Toggle("Planned-time notification", isOn: Binding(get: { model.preferences.backgroundAlerts }, set: { enabled in
                        if enabled { permission = .completion } else {
                            model.updatePreferences { $0.backgroundAlerts = false }
                            model.notifications.cancelFinish()
                        }
                    }))
                } header: { PauseSectionHeader(title: "Your meditation") } footer: { PauseSectionFooter(text: "Pause keeps your screen awake during an active meditation. If you choose Silence with an ending bell, it holds a muted audio stream so the bell can play if you lock your iPhone. This is experimental; test it before relying on it.") }
                    .listRowBackground(Palette.paper).listRowSeparatorTint(Palette.line.opacity(0.55))
                Section {
                    Toggle("Daily reminder", isOn: Binding(get: { model.preferences.reminderEnabled }, set: { enabled in
                        if enabled { permission = .reminder } else { model.updatePreferences { $0.reminderEnabled = false }; Task { await model.updateReminder() } }
                    }))
                    if model.preferences.reminderEnabled { DatePicker("A quiet time", selection: reminderDate, displayedComponents: .hourAndMinute) }
                } header: { PauseSectionHeader(title: "A gentle nudge") } footer: { PauseSectionFooter(text: "A reminder, never a demand.") }
                    .listRowBackground(Palette.paper).listRowSeparatorTint(Palette.line.opacity(0.55))
                Section {
                    Button { do { exportDocument = BackupDocument(data: try model.makeBackup()); exporting = true } catch { message = error.localizedDescription } } label: { Label("Export a backup", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Import a backup", systemImage: "square.and.arrow.down") }
                } header: { PauseSectionHeader(title: "Keep your moments") } footer: { PauseSectionFooter(text: "History is saved on this iPhone. Save a backup to Files or iCloud Drive before deleting the app or changing phones. Updating Pause in place keeps your history.") }
                    .listRowBackground(Palette.paper).listRowSeparatorTint(Palette.line.opacity(0.55))
                Section {
                    HStack { Text("Pause").font(.system(.title2, design: .serif)); Spacer(); Text("1.0").foregroundStyle(Palette.secondary) }
                    Text("A practice, not a perfect record.").font(.system(.subheadline, design: .serif)).italic().foregroundStyle(Palette.secondary)
                }
                    .listRowBackground(Palette.paper).listRowSeparatorTint(Palette.line.opacity(0.55))
            }.pauseFormSurface().navigationTitle("Make it yours").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("Make it yours").font(.system(.headline, design: .serif)).foregroundStyle(Palette.ink) }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "Pause-backup-\(Day.key(Date()))") { result in
                    if case .failure(let error) = result { message = error.localizedDescription }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 20_000_000 else { throw BackupError.invalid("This backup is too large.") }
                        let data = try Data(contentsOf: url); let backup = try Backup.decode(data)
                        pendingImport = data
                        importSummary = "Merge \(backup.sessions.count) sessions and restore saved preferences? Matching sessions use the most recently edited version. Existing sessions are kept."
                        importConfirmation = true
                    } catch { message = error.localizedDescription }
                }
                .confirmationDialog("Restore your moments", isPresented: $importConfirmation, titleVisibility: .visible) {
                    Button("Merge backup") {
                        do { if let pendingImport { try model.importBackup(pendingImport) }; pendingImport = nil; message = "Your backup has been merged." }
                        catch { message = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) { pendingImport = nil }
                } message: { Text(importSummary) }
                .alert("Your backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
                .sheet(item: $permission) { purpose in PermissionView(purpose: purpose) }
        }.tint(Palette.dialSage).presentationBackground(Palette.cream)
    }
}
enum SoundOptions {
    static let ambients = [("none", "Silence", "speaker.slash"), ("rain", "Soft rain", "cloud.rain"), ("ocean", "Ocean tide", "water.waves"), ("ambient", "Warm ambient", "waveform")]
    static let endings = [("none", "Silence"), ("bell", "Gentle bell"), ("bowl", "Singing bowl"), ("chime", "Soft chime")]
    static func ambientName(_ key: String) -> String { ambients.first { $0.0 == key }?.1 ?? "Silence" }
}
struct SoundSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var previewError: String?
    var body: some View {
        Form {
            Section {
                ForEach(SoundOptions.ambients, id: \.0) { option in
                    Button { model.updatePreferences { $0.ambient = option.0 }; preview(option.0, volume: model.preferences.ambientVolume, looping: option.0 != "none") } label: {
                        HStack { Label(option.1, systemImage: option.2); Spacer(); if model.preferences.ambient == option.0 { Image(systemName: "checkmark").foregroundStyle(Palette.dialSage) } }.foregroundStyle(Palette.ink)
                    }.accessibilityAddTraits(model.preferences.ambient == option.0 ? [.isSelected] : [])
                }
                VStack(alignment: .leading) {
                    Text("Ambient volume").font(.subheadline)
                    Slider(value: Binding(get: { model.preferences.ambientVolume }, set: { value in
                        model.updatePreferences { $0.ambientVolume = value }
                        model.audio.setPreviewVolume(model.preferences.ambient, volume: value)
                    }), in: 0...1, onEditingChanged: { editing in
                        if editing { previewIfNeeded(model.preferences.ambient, volume: model.preferences.ambientVolume, looping: true) }
                    })
                        .accessibilityLabel("Ambient volume")
                }
            } header: { PauseSectionHeader(title: "While you meditate") } footer: { PauseSectionFooter(text: "Tap a sound or move the slider to preview it. The ambient preview loops while this screen is open. All sounds are available offline.") }
                .listRowBackground(Palette.paper).listRowSeparatorTint(Palette.line.opacity(0.55))
            Section {
                ForEach(SoundOptions.endings, id: \.0) { option in
                    Button { model.updatePreferences { $0.ending = option.0 }; preview(option.0, volume: model.preferences.endingVolume) } label: {
                        HStack { Text(option.1); Spacer(); if model.preferences.ending == option.0 { Image(systemName: "checkmark").foregroundStyle(Palette.dialSage) } }.foregroundStyle(Palette.ink)
                    }.accessibilityAddTraits(model.preferences.ending == option.0 ? [.isSelected] : [])
                }
                VStack(alignment: .leading) {
                    Text("Bell volume").font(.subheadline)
                    Slider(value: Binding(get: { model.preferences.endingVolume }, set: { value in
                        model.updatePreferences { $0.endingVolume = value }
                        model.audio.setPreviewVolume(model.preferences.ending, volume: value)
                    }), in: 0...1, onEditingChanged: { editing in
                        if editing { previewIfNeeded(model.preferences.ending, volume: model.preferences.endingVolume) }
                    })
                        .accessibilityLabel("Bell volume")
                }
                Toggle("A bell at the beginning", isOn: Binding(get: { model.preferences.startBell }, set: { value in model.updatePreferences { $0.startBell = value } }))
            } header: { PauseSectionHeader(title: "A gentle ending") } footer: { PauseSectionFooter(text: "Move the slider to preview the bell at its current volume. It rings at your planned time; the timer keeps running until you pause and end the session. If you lock your phone manually, a notification may be silenced by your iPhone. Set bell volume to zero for no ending sound.") }
                .listRowBackground(Palette.paper).listRowSeparatorTint(Palette.line.opacity(0.55))
        }.pauseFormSurface().navigationTitle("Sounds & bells").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Text("Sounds & bells").font(.system(.headline, design: .serif)).foregroundStyle(Palette.ink) } }
            .onDisappear { if model.active == nil { model.audio.stop() } }
            .alert("Sound unavailable", isPresented: Binding(get: { previewError != nil }, set: { if !$0 { previewError = nil } })) { Button("OK") { previewError = nil } } message: { Text(previewError ?? "") }
    }
    private func preview(_ name: String, volume: Float, looping: Bool = false) { do { try model.audio.previewSound(name, volume: volume, looping: looping) } catch { previewError = error.localizedDescription } }
    private func previewIfNeeded(_ name: String, volume: Float, looping: Bool = false) { do { try model.audio.previewSoundIfNeeded(name, volume: volume, looping: looping) } catch { previewError = error.localizedDescription } }
}
