import SwiftUI

struct SessionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existing: SessionRecord?
    @State private var date: Date
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var reflection: String
    @State private var error: String?
    init(date: Date, existing: SessionRecord? = nil) {
        self.existing = existing
        _date = State(initialValue: date)
        _minutes = State(initialValue: existing.map { Int($0.seconds) / 60 } ?? 10)
        _seconds = State(initialValue: existing.map { Int($0.seconds) % 60 } ?? 0)
        _reflection = State(initialValue: existing?.reflection ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("When", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    Stepper("\(minutes) minutes", value: $minutes, in: 0...1440)
                    Stepper("\(seconds) seconds", value: $seconds, in: 0...59)
                } header: { PauseSectionHeader(title: "A moment worth keeping") } footer: { PauseSectionFooter(text: "Saved sessions contribute to the daily goal for their date.") }
                    .listRowBackground(Palette.paper).listRowSeparatorTint(Palette.line.opacity(0.55))
                Section {
                    TextField("How was your moment of stillness?", text: $reflection, axis: .vertical).lineLimit(4...10)
                        .onChange(of: reflection) { _, text in if text.count > 10_000 { reflection = String(text.prefix(10_000)) } }
                } header: { PauseSectionHeader(title: "Reflection · optional") }
                    .listRowBackground(Palette.paper).listRowSeparatorTint(Palette.line.opacity(0.55))
                if let error { Text(error).foregroundStyle(.red).listRowBackground(Palette.paper) }
            }.pauseFormSurface()
                .navigationTitle(existing == nil ? "Add meditation" : "Edit meditation").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text(existing == nil ? "Add meditation" : "Edit meditation").font(.system(.headline, design: .serif)).foregroundStyle(Palette.ink) }
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(minutes * 60 + seconds < 1 || minutes * 60 + seconds > 86_400).accessibilityIdentifier("saveSession") }
                }
        }.tint(Palette.dialSage).presentationBackground(Palette.cream)
    }
    private func save() {
        // Preserve a recorded local day unless the user explicitly changes the timestamp.
        let day = existing.map { $0.completedAt == date ? $0.dayKey : Day.key(date) } ?? Day.key(date)
        let record = SessionRecord(id: existing?.id ?? UUID(), completedAt: date, dayKey: day,
                                   seconds: Double(minutes * 60 + seconds), reflection: reflection.trimmingCharacters(in: .whitespacesAndNewlines), source: existing?.source ?? "manual")
        if model.saveSession(record) { dismiss() } else { error = model.errorMessage; model.errorMessage = nil }
    }
}
