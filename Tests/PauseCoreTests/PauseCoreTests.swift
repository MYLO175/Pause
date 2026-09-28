import XCTest
#if canImport(PauseCore)
@testable import PauseCore
#else
@testable import Pause
import AVFoundation
import UserNotifications
#endif

final class PauseCoreTests: XCTestCase {
    func testSilentEndingNeedsMutedBackgroundAudioOnlyWhenAudibleEndingIsSelected() {
        var preferences = Preferences()
        XCTAssertFalse(preferences.backgroundAlerts)
        XCTAssertTrue(preferences.needsSilentSessionAudio)
        preferences.ambient = "rain"
        XCTAssertFalse(preferences.needsSilentSessionAudio)
        preferences.ambient = "none"; preferences.ending = "none"
        XCTAssertFalse(preferences.needsSilentSessionAudio)
        preferences.ending = "bell"; preferences.endingVolume = 0
        XCTAssertFalse(preferences.needsSilentSessionAudio)
    }
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/London")!; return c
    }
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func session(_ key: String, seconds: Double = 600) -> SessionRecord {
        SessionRecord(completedAt: Day.date(key, calendar: calendar)!, dayKey: key, seconds: seconds)
    }
    func testDialTurnsAcrossTwelveAndClampsWithoutDeadTravel() {
        var dial = DialAdjustment(minutes: 10)
        dial.turn(to: 179 * .pi / 180)
        dial.turn(to: -175 * .pi / 180)
        XCTAssertEqual(dial.selectedMinutes, 11)
        XCTAssertEqual(dial.rotation, 6, accuracy: 0.001)
        var minimum = DialAdjustment(minutes: 1)
        minimum.turn(to: 0); minimum.turn(to: -.pi / 2)
        XCTAssertEqual(minimum.selectedMinutes, 0)
        minimum.turn(to: -.pi / 2 + .pi / 30)
        XCTAssertEqual(minimum.selectedMinutes, 1)
        var maximum = DialAdjustment(minutes: 179)
        maximum.turn(to: 0); maximum.turn(to: .pi / 2)
        XCTAssertEqual(maximum.selectedMinutes, 180)
        maximum.turn(to: .pi / 2 - .pi / 30)
        XCTAssertEqual(maximum.selectedMinutes, 179)
    }
    func testPracticeTotalChangesUnitsAtHourAndDay() {
        XCTAssertEqual(PracticeTotal(seconds: 3599).unit, "total mins")
        XCTAssertEqual(PracticeTotal(seconds: 3600).unit, "total hours")
        XCTAssertEqual(PracticeTotal(seconds: 86400).unit, "total days")
        XCTAssertEqual(PracticeTotal(seconds: 0).value, "0")
    }
    func testTodayCanRemainIncompleteWithoutLosingStreak() {
        let p = PracticeProgress(sessions: [session("2026-09-17"), session("2026-09-18")], goals: [.baseline], calendar: calendar)
        XCTAssertEqual(p.currentStreak(now: date("2026-09-19T12:00:00Z")), 2)
        XCTAssertEqual(p.currentStreak(now: date("2026-09-20T12:00:00Z")), 0)
        XCTAssertEqual(p.longestStreak, 2)
    }
    func testPartialSessionsAddUpAndEditsRecalculate() {
        let a = session("2026-09-18", seconds: 240); var b = session("2026-09-18", seconds: 360)
        var p = PracticeProgress(sessions: [a, b], goals: [.baseline], calendar: calendar)
        XCTAssertTrue(p.reached("2026-09-18"))
        b.seconds = 359; p.sessions = [a, b]
        XCTAssertFalse(p.reached("2026-09-18"))
        p.sessions = []; XCTAssertEqual(p.longestStreak, 0)
    }
    func testCurrentGoalReevaluatesHistoryAndStreaks() {
        let goals = [
            GoalRecord.baseline,
            GoalRecord(effectiveDay: "2026-09-19", minutes: 10, updatedAt: date("2026-09-19T12:00:00Z")),
            GoalRecord(effectiveDay: "2026-09-20", minutes: 5, updatedAt: date("2026-09-20T12:00:00Z"))
        ]
        let p = PracticeProgress(sessions: [
            session("2026-09-18", seconds: 420),
            session("2026-09-19", seconds: 420)
        ], goals: goals, calendar: calendar)
        XCTAssertEqual(p.goal(on: "2026-09-18"), 5)
        XCTAssertTrue(p.reached("2026-09-18")); XCTAssertTrue(p.reached("2026-09-19"))
        XCTAssertEqual(p.currentStreak(now: date("2026-09-20T12:00:00Z")), 2)
        XCTAssertEqual(p.longestStreak, 2)
    }
    func testStreaksAcrossDSTAndYearBoundary() {
        for keys in [["2026-03-28", "2026-03-29", "2026-03-30"], ["2026-10-24", "2026-10-25", "2026-10-26"], ["2025-12-31", "2026-01-01", "2026-01-02"]] {
            let p = PracticeProgress(sessions: keys.map { session($0) }, goals: [.baseline], calendar: calendar)
            XCTAssertEqual(p.longestStreak, 3)
            XCTAssertEqual(p.currentStreak(now: Day.date(keys.last!, calendar: calendar)!), 3)
        }
    }
    func testStoredLocalDaysSurviveTimeZoneChange() {
        let stored = session("2026-09-18")
        var pacific = calendar; pacific.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        let p = PracticeProgress(sessions: [stored], goals: [.baseline], calendar: pacific)
        XCTAssertTrue(p.reached("2026-09-18"))
    }
    func testTimerExcludesPauseAndKeepsCountingAfterDeadline() throws {
        let start = date("2026-09-19T10:00:00Z")
        var timer = ActiveSession(minutes: 10, now: start)
        timer.pause(at: start.addingTimeInterval(120))
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(900)), 120)
        timer.resume(at: start.addingTimeInterval(900))
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(1380))
        let recovered = try JSONDecoder().decode(ActiveSession.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(recovered.elapsed(at: start.addingTimeInterval(2000)), 1220)
        XCTAssertEqual(recovered.record(at: start.addingTimeInterval(2000)).completedAt, start.addingTimeInterval(2000))
        XCTAssertEqual(recovered.record(at: start.addingTimeInterval(2000)).seconds, 1220)
        XCTAssertEqual(recovered.record(at: start.addingTimeInterval(2000)).id, timer.id)
    }
    func testManualEndUsesActualEndDayAcrossMidnight() {
        let start = date("2026-09-18T22:58:00Z") // 23:58 London
        let timer = ActiveSession(minutes: 5, now: start, timeZoneID: "Europe/London")
        let record = timer.record(at: start.addingTimeInterval(36_000))
        XCTAssertEqual(record.dayKey, "2026-09-19")
        XCTAssertEqual(record.seconds, 36_000)
    }
    func testBackwardsClockDoesNotProduceNegativeDuration() {
        let now = Date(); let timer = ActiveSession(minutes: 10, now: now)
        XCTAssertEqual(timer.elapsed(at: now.addingTimeInterval(-50)), 0)
    }
    func testBackupRoundTripMergeAndPreferences() throws {
        var record = session("2026-09-18"); record.reflection = "A quieter mind 🌱"; record.updatedAt = date("2026-09-18T14:00:00Z")
        var preferences = Preferences(); preferences.ambient = "ocean"
        let backup = Backup(sessions: [record], goals: [.baseline], preferences: preferences)
        let decoded = try Backup.decode(backup.data(), now: date("2026-09-20T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(decoded.sessions, [record]); XCTAssertEqual(decoded.preferences, preferences)
        XCTAssertEqual(decoded.mergedSessions(with: [record]).count, 1)
        var newer = record; newer.reflection = "Edited"; newer.updatedAt = date("2026-09-19T14:00:00Z")
        XCTAssertEqual(decoded.mergedSessions(with: [newer]), [newer])
        XCTAssertEqual(decoded.mergedGoals(with: [.baseline]).count, 1)
    }
    func testInvalidBackupsAreRejectedBeforeMerge() throws {
        let now = date("2026-09-20T12:00:00Z")
        var b = Backup(sessions: [session("2026-09-18")], goals: [.baseline], preferences: Preferences())
        b.version = 99; XCTAssertThrowsError(try b.validate(now: now))
        b.version = 1; b.sessions[0].seconds = -3; XCTAssertThrowsError(try b.validate(now: now))
        b.sessions[0].seconds = 600; b.sessions[0].completedAt = now.addingTimeInterval(10); XCTAssertThrowsError(try b.validate(now: now))
        b.sessions = [session("2026-09-18")]; b.sessions.append(b.sessions[0]); XCTAssertThrowsError(try b.validate(now: now))
        b.sessions = []; b.preferences.ambientVolume = .nan; XCTAssertThrowsError(try b.validate(now: now))
        XCTAssertThrowsError(try Backup.decode(Data("not json".utf8)))
        XCTAssertNil(Day.date("2026-02-30", calendar: calendar))
    }
    func testMilestonesDerivedFromSavedSessions() {
        let sessions = (0..<10).map { session(Day.key(Day.offset(date("2026-09-19T12:00:00Z"), days: -$0, calendar: calendar), calendar: calendar)) }
        let p = PracticeProgress(sessions: sessions, goals: [.baseline], calendar: calendar)
        XCTAssertEqual(p.milestones, ["7-day streak", "10 sessions"])
    }
}
#if canImport(Pause)
@MainActor final class PersistenceTests: XCTestCase {
    func testSilentEndingDoesNotScheduleAnUnrequestedNotification() {
        let now = Date()
        XCTAssertNil(Notifications.finishRequest(deadline: now.addingTimeInterval(600), preferences: Preferences(), audioHandlesSound: false, now: now))
    }
    func testCompletionDeliveryRespectsSilenceAndAvoidsDuplicateAudio() throws {
        let deadline = Date().addingTimeInterval(600)
        var preferences = Preferences()
        preferences.endingVolume = 0
        XCTAssertNil(Notifications.finishRequest(deadline: deadline, preferences: preferences, audioHandlesSound: false))
        preferences.backgroundAlerts = true
        let muted = try XCTUnwrap(Notifications.finishRequest(deadline: deadline, preferences: preferences, audioHandlesSound: false))
        XCTAssertNil(muted.content.sound)
        preferences.endingVolume = 0.65; preferences.ambient = "rain"
        let ambient = try XCTUnwrap(Notifications.finishRequest(deadline: deadline, preferences: preferences, audioHandlesSound: true))
        XCTAssertNil(ambient.content.sound)
        preferences.backgroundAlerts = false
        XCTAssertNil(Notifications.finishRequest(deadline: deadline, preferences: preferences, audioHandlesSound: true))
        XCTAssertNil(Notifications.finishRequest(deadline: Date().addingTimeInterval(-1), preferences: Preferences(), audioHandlesSound: false))
    }
    func testRepeatedRecoverySaveIsIdempotent() throws {
        let store = try Persistence(inMemory: true)
        let record = SessionRecord(completedAt: Date(), dayKey: Day.key(Date()), seconds: 600)
        try store.save(record); try store.save(record)
        XCTAssertEqual(try store.sessions().count, 1)
        var edited = record; edited.reflection = "Still here"; try store.save(edited)
        XCTAssertEqual(try store.sessions().first?.reflection, "Still here")
    }
    func testImportIsIdempotentAndKeepsExisting() throws {
        let store = try Persistence(inMemory: true)
        let record = SessionRecord(completedAt: Date().addingTimeInterval(-1000), dayKey: Day.key(Date()), seconds: 600)
        try store.save(record)
        let other = SessionRecord(completedAt: Date().addingTimeInterval(-2000), dayKey: Day.key(Date()), seconds: 300)
        let backup = Backup(sessions: [other], goals: [.baseline], preferences: Preferences())
        try store.merge(backup); try store.merge(backup)
        XCTAssertEqual(try store.sessions().count, 2)
        XCTAssertEqual(try store.goals().count, 1)
    }
    func testRecoveredElapsedTimerStaysActiveAfterPlannedEnd() throws {
        let store = try Persistence(inMemory: true)
        let suite = "PauseRecovery-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = Preferences(); preferences.ending = "none"
        defaults.set(try JSONEncoder().encode(preferences), forKey: "preferences")
        let timer = ActiveSession(minutes: 1, now: Date().addingTimeInterval(-120))
        let data = try JSONEncoder().encode(timer)
        defaults.set(data, forKey: "activeSession")
        let firstLaunch = AppModel(persistence: store, defaults: defaults)
        XCTAssertEqual(firstLaunch.active?.id, timer.id)
        XCTAssertGreaterThanOrEqual(firstLaunch.active?.elapsed(at: Date()) ?? 0, 120)
        XCTAssertTrue(firstLaunch.sessions.isEmpty)
        // Reopening the app keeps the same active session and does not save it automatically.
        defaults.set(data, forKey: "activeSession")
        let secondLaunch = AppModel(persistence: store, defaults: defaults)
        XCTAssertEqual(secondLaunch.active?.id, timer.id)
        XCTAssertTrue(secondLaunch.sessions.isEmpty)
    }
    func testPausedTimerSurvivesRelaunchWithoutAccumulatingTime() throws {
        let store = try Persistence(inMemory: true)
        let suite = "PauseRecovery-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date().addingTimeInterval(-3600)
        var timer = ActiveSession(minutes: 10, now: start)
        timer.pause(at: start.addingTimeInterval(30))
        defaults.set(try JSONEncoder().encode(timer), forKey: "activeSession")
        let model = AppModel(persistence: store, defaults: defaults)
        XCTAssertTrue(model.active?.isPaused == true)
        XCTAssertEqual(model.active?.elapsed(at: Date()), 30)
        XCTAssertTrue(model.sessions.isEmpty)
        model.discard()
    }
    func testStoreReopensWithoutLosingHistoryOrGoals() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.store")
        let record = SessionRecord(completedAt: Date(), dayKey: Day.key(Date()), seconds: 600, reflection: "Keep this moment")
        let tomorrow = Day.key(Day.offset(Date(), days: 1))
        do {
            let first = try Persistence(storeURL: url)
            try first.save(record)
            try first.saveGoal(.init(effectiveDay: tomorrow, minutes: 15))
        }
        let reopened = try Persistence(storeURL: url)
        XCTAssertEqual(try reopened.sessions().first, record)
        XCTAssertEqual(try reopened.goals().first { $0.effectiveDay == tomorrow }?.minutes, 15)
    }
    func testBundledAudioIsReadableAndNotificationSoundsAreShort() throws {
        for name in ["rain", "ocean", "ambient", "bell", "bowl", "chime"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "wav"))
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0)
            if ["bell", "bowl", "chime"].contains(name) { XCTAssertLessThan(player.duration, 30) }
        }
    }
    func testPendingGoalUpdatesKeepIdentity() throws {
        let store = try Persistence(inMemory: true)
        let day = Day.key(Day.offset(Date(), days: 1))
        try store.saveGoal(.init(effectiveDay: day, minutes: 15))
        let id = try store.goals().first { $0.effectiveDay == day }!.id
        try store.saveGoal(.init(effectiveDay: day, minutes: 20))
        let goal = try store.goals().first { $0.effectiveDay == day }!
        XCTAssertEqual(goal.id, id); XCTAssertEqual(goal.minutes, 20)
    }
}
#endif
