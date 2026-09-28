import Foundation

public enum Day {
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: components), self.key(date, calendar: calendar) == key else { return nil }
        return date
    }
    public static func offset(_ date: Date, days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }
}

public struct SessionRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var completedAt: Date
    public var dayKey: String
    public var seconds: Double
    public var reflection: String
    public var source: String
    public var updatedAt: Date
    public init(id: UUID = UUID(), completedAt: Date, dayKey: String, seconds: Double, reflection: String = "", source: String = "timer", updatedAt: Date = Date()) {
        self.id = id; self.completedAt = completedAt; self.dayKey = dayKey; self.seconds = seconds
        self.reflection = reflection; self.source = source; self.updatedAt = updatedAt
    }
}

public struct GoalRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var effectiveDay: String
    public var minutes: Int
    public var updatedAt: Date
    public init(id: UUID = UUID(), effectiveDay: String, minutes: Int, updatedAt: Date = Date()) {
        self.id = id; self.effectiveDay = effectiveDay; self.minutes = minutes; self.updatedAt = updatedAt
    }
    public static let baselineID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    public static var baseline: GoalRecord { .init(id: baselineID, effectiveDay: "0001-01-01", minutes: 10, updatedAt: .distantPast) }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var durationMinutes = 10
    public var ambient = "none"
    public var ambientVolume: Float = 0.45
    public var ending = "bell"
    public var endingVolume: Float = 0.65
    public var startBell = false
    public var backgroundAlerts = false
    public var reminderEnabled = false
    public var reminderHour = 20
    public var reminderMinute = 0
    // A silent session needs a muted playback stream to keep the ending player alive in the background.
    public var needsSilentSessionAudio: Bool { ambient == "none" && ending != "none" && endingVolume > 0 }
    public init() {}
}
