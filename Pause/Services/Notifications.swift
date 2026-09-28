import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    override init() { super.init(); center.delegate = self }
    func request() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func cancelFinish() { center.removePendingNotificationRequests(withIdentifiers: ["meditation-finish"]) }
    func scheduleFinish(deadline: Date, preferences: Preferences, audioHandlesSound: Bool) async throws {
        cancelFinish()
        guard let request = Self.finishRequest(deadline: deadline, preferences: preferences, audioHandlesSound: audioHandlesSound) else { return }
        try await center.add(request)
    }
    static func finishRequest(deadline: Date, preferences: Preferences, audioHandlesSound: Bool, now: Date = Date()) -> UNNotificationRequest? {
        guard preferences.backgroundAlerts, deadline > now else { return nil }
        let content = UNMutableNotificationContent(); content.title = "Your planned time is here."
        content.body = "Take your time. Your meditation continues until you end it."
        if preferences.ending != "none" && preferences.endingVolume > 0 && !audioHandlesSound {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(preferences.ending).wav"))
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSince(now)), repeats: false)
        return UNNotificationRequest(identifier: "meditation-finish", content: content, trigger: trigger)
    }
    func updateReminder(_ preferences: Preferences) async throws {
        center.removePendingNotificationRequests(withIdentifiers: ["daily-reminder"])
        guard preferences.reminderEnabled else { return }
        let content = UNMutableNotificationContent(); content.title = "A little room to breathe."
        content.body = "Your next quiet moment is here when you are."; content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: preferences.reminderHour, minute: preferences.reminderMinute), repeats: true)
        try await center.add(UNNotificationRequest(identifier: "daily-reminder", content: content, trigger: trigger))
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier == "meditation-finish" ? [] : [.banner, .sound]
    }
}

/// Removes any alarms left behind by the previous AlarmKit-based test build.
@MainActor enum LegacyAlarmCleanup {
    static func cancelAll() {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        let manager = AlarmManager.shared
        guard let alarms = try? manager.alarms else { return }
        for alarm in alarms {
            do { try manager.cancel(id: alarm.id) } catch { }
            let soundsDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Sounds", isDirectory: true)
            try? FileManager.default.removeItem(at: soundsDirectory.appendingPathComponent("Pause-\(alarm.id.uuidString).wav"))
        }
        #endif
    }
}
