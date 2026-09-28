import Foundation

public struct ActiveSession: Codable, Equatable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var targetSeconds: Double
    public var accumulated: Double
    public var segmentStartedAt: Date?
    public var timeZoneID: String
    // Optional so active-session data written by earlier versions still decodes.
    public var plannedEndHandled: Bool?
    public init(minutes: Int, now: Date = Date(), timeZoneID: String = TimeZone.current.identifier) {
        id = UUID(); startedAt = now; targetSeconds = Double(minutes * 60)
        accumulated = 0; segmentStartedAt = now; self.timeZoneID = timeZoneID; plannedEndHandled = false
    }
    public var isPaused: Bool { segmentStartedAt == nil }
    public var hasHandledPlannedEnd: Bool { plannedEndHandled == true }
    public func elapsed(at date: Date) -> Double {
        accumulated + (segmentStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
    public var deadline: Date? { segmentStartedAt?.addingTimeInterval(max(0, targetSeconds - accumulated)) }
    public mutating func pause(at date: Date) { accumulated = elapsed(at: date); segmentStartedAt = nil }
    public mutating func resume(at date: Date) {
        guard isPaused else { return }; segmentStartedAt = date; timeZoneID = TimeZone.current.identifier
    }
    public func record(at date: Date) -> SessionRecord {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return SessionRecord(id: id, completedAt: date, dayKey: Day.key(date, calendar: calendar), seconds: elapsed(at: date))
    }
}
