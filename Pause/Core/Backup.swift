import Foundation

public struct Backup: Codable, Equatable, Sendable {
    public var version = 1
    public var exportedAt = Date()
    public var sessions: [SessionRecord]
    public var goals: [GoalRecord]
    public var preferences: Preferences
    public init(sessions: [SessionRecord], goals: [GoalRecord], preferences: Preferences) {
        self.sessions = sessions; self.goals = goals; self.preferences = preferences
    }
    public func data() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    public static func decode(_ data: Data, now: Date = Date(), calendar: Calendar = .current) throws -> Backup {
        guard data.count <= 20_000_000 else { throw BackupError.invalid("This backup is too large.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)
        try backup.validate(now: now, calendar: calendar)
        return backup
    }
    public func validate(now: Date = Date(), calendar: Calendar = .current) throws {
        guard version == 1 else { throw BackupError.invalid("This backup version isn’t supported.") }
        guard Set(sessions.map(\.id)).count == sessions.count, Set(goals.map(\.id)).count == goals.count else {
            throw BackupError.invalid("The backup contains duplicate record IDs.")
        }
        // A recorded local date may be tomorrow in the importing device's timezone.
        let latestLocalDay = Day.key(Day.offset(now, days: 1, calendar: calendar), calendar: calendar)
        for s in sessions {
            guard s.seconds.isFinite, s.seconds >= 1,
                  s.completedAt <= now, Day.date(s.dayKey, calendar: calendar) != nil,
                  s.dayKey <= latestLocalDay, s.reflection.count <= 10_000,
                  ["timer", "manual"].contains(s.source) else { throw BackupError.invalid("A session contains invalid or future-dated data.") }
        }
        for g in goals {
            guard (1...180).contains(g.minutes), Day.date(g.effectiveDay, calendar: calendar) != nil,
                  g.effectiveDay <= latestLocalDay else { throw BackupError.invalid("A daily goal is invalid.") }
        }
        let p = preferences
        guard (0...180).contains(p.durationMinutes), ["none", "rain", "ocean", "ambient"].contains(p.ambient),
              ["none", "bell", "bowl", "chime"].contains(p.ending),
              p.ambientVolume.isFinite, (0...1).contains(p.ambientVolume),
              p.endingVolume.isFinite, (0...1).contains(p.endingVolume),
              (0...23).contains(p.reminderHour), (0...59).contains(p.reminderMinute) else { throw BackupError.invalid("The saved preferences are invalid.") }
    }
    public func mergedSessions(with existing: [SessionRecord]) -> [SessionRecord] {
        var result = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for record in sessions where result[record.id].map({ $0.updatedAt < record.updatedAt }) ?? true { result[record.id] = record }
        return result.values.sorted { $0.completedAt < $1.completedAt }
    }
    public func mergedGoals(with existing: [GoalRecord]) -> [GoalRecord] {
        var result = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for record in goals where result[record.id].map({ $0.updatedAt < record.updatedAt }) ?? true { result[record.id] = record }
        return result.values.sorted { $0.effectiveDay < $1.effectiveDay }
    }
}
public enum BackupError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
