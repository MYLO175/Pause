import SwiftUI

@main struct PauseApp: App {
    @State private var model: AppModel?
    @State private var startupError: String?
    init() {
        do {
            #if DEBUG
            let testing = ProcessInfo.processInfo.arguments.contains("-ui-testing")
            let store = try Persistence(inMemory: testing)
            let defaults = testing ? UserDefaults(suiteName: "PauseUITests")! : .standard
            if testing { defaults.removePersistentDomain(forName: "PauseUITests") }
            let instance = AppModel(persistence: store, defaults: defaults)
            if ProcessInfo.processInfo.arguments.contains("-seed-history") {
                let calendar = Calendar.current
                for offset in [0, 1, 2, 3, 4, 5, 6, 8, 9, 11, 12, 15, 16, 18] {
                    let date = Day.offset(Date().addingTimeInterval(-600), days: -offset, calendar: calendar)
                    _ = instance.saveSession(SessionRecord(completedAt: date, dayKey: Day.key(date), seconds: Double([600, 900, 1200, 300][offset % 4]), source: "manual"))
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-completion") {
                let session = SessionRecord(completedAt: Date(), dayKey: Day.key(Date()), seconds: 600)
                _ = instance.saveSession(session); instance.completed = session
            }
            _model = State(initialValue: instance)
            #else
            _model = State(initialValue: AppModel(persistence: try Persistence()))
            #endif
        } catch { _startupError = State(initialValue: error.localizedDescription) }
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if let model { RootView().environment(model) }
                else {
                    ContentUnavailableView {
                        Label("Your moments are safe.", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("Pause couldn’t open its local history. Close and reopen the app. Don’t delete it, as that removes its data.\n\n\(startupError ?? "Unknown storage error")")
                    }
                }
            }.preferredColorScheme(.light).tint(Palette.sage)
        }
    }
}
