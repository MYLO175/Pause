import Foundation

public struct PracticeProgress {
    public var sessions: [SessionRecord]
    public var goals: [GoalRecord]
    public var calendar: Calendar
    public init(sessions: [SessionRecord], goals: [GoalRecord], calendar: Calendar = .current) {
        self.sessions = sessions; self.goals = goals; self.calendar = calendar
    }
    public var secondsByDay: [String: Double] {
        Dictionary(grouping: sessions, by: \.dayKey).mapValues { $0.reduce(0) { $0 + $1.seconds } }
    }
    public var totalSeconds: Double { sessions.reduce(0) { $0 + $1.seconds } }
    public var currentGoal: Int {
        goals.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
            if $0.effectiveDay != $1.effectiveDay { return $0.effectiveDay < $1.effectiveDay }
            return $0.id.uuidString < $1.id.uuidString
        }.last?.minutes ?? 10
    }
    // Goal changes re-score every day in the journal, including days before the change.
    public func goal(on _: String) -> Int { currentGoal }
    public func reached(_ day: String) -> Bool { (secondsByDay[day] ?? 0) + 0.001 >= Double(goal(on: day) * 60) }
    public var qualifyingDays: Set<String> {
        Set(secondsByDay.compactMap { $0.value + 0.001 >= Double(goal(on: $0.key) * 60) ? $0.key : nil })
    }
    public func currentStreak(now: Date = Date()) -> Int {
        let days = qualifyingDays
        var cursor = now
        if !days.contains(Day.key(cursor, calendar: calendar)) { cursor = Day.offset(cursor, days: -1, calendar: calendar) }
        var count = 0
        while days.contains(Day.key(cursor, calendar: calendar)) {
            count += 1; cursor = Day.offset(cursor, days: -1, calendar: calendar)
        }
        return count
    }
    public var longestStreak: Int {
        var previous: Date?; var running = 0; var longest = 0
        for key in qualifyingDays.sorted() {
            guard let date = Day.date(key, calendar: calendar) else { continue }
            let adjacent = previous.map { Day.key(Day.offset($0, days: 1, calendar: calendar), calendar: calendar) == key } ?? false
            running = adjacent ? running + 1 : 1; longest = max(longest, running); previous = date
        }
        return longest
    }
    public var milestones: [String] {
        [7, 30, 100].filter { longestStreak >= $0 }.map { "\($0)-day streak" }
        + [10, 50, 100].filter { sessions.count >= $0 }.map { "\($0) sessions" }
    }
}
