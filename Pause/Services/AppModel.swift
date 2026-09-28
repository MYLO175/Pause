import Foundation
import Observation
import AVFoundation

@MainActor @Observable final class AppModel {
    var sessions: [SessionRecord] = []
    var goals: [GoalRecord] = []
    var preferences: Preferences
    var active: ActiveSession?
    var now = Date()
    var completed: SessionRecord?
    var errorMessage: String?
    var foreground = true
    var permissionPurpose: PermissionPurpose?
    enum PermissionPurpose: String, Identifiable { case completion, reminder; var id: String { rawValue } }
    @ObservationIgnored let persistence: Persistence
    @ObservationIgnored let audio = AudioService()
    @ObservationIgnored let notifications = Notifications()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var notificationTask: Task<Void, Never>?

    init(persistence: Persistence, defaults: UserDefaults = .standard) {
        self.persistence = persistence; self.defaults = defaults
        preferences = defaults.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        active = defaults.data(forKey: "activeSession").flatMap { try? JSONDecoder().decode(ActiveSession.self, from: $0) }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue { Task { @MainActor in self?.pause() } }
        }
        recover()
    }
    deinit {
        timer?.invalidate()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }
    var progress: PracticeProgress { PracticeProgress(sessions: sessions, goals: goals) }
    var today: String { Day.key(now) }
    var todayMinutes: Double { (progress.secondsByDay[today] ?? 0) / 60 }
    var remaining: Double { active.map { max(0, $0.targetSeconds - $0.elapsed(at: now)) } ?? Double(preferences.durationMinutes * 60) }
    var dailyGoal: Int { progress.currentGoal }
    func reload() {
        do { sessions = try persistence.sessions(); goals = try persistence.goals() }
        catch { errorMessage = "Your history couldn’t be read. \(error.localizedDescription)" }
    }
    func updatePreferences(_ change: (inout Preferences) -> Void) {
        change(&preferences)
        do { defaults.set(try JSONEncoder().encode(preferences), forKey: "preferences") }
        catch { errorMessage = error.localizedDescription }
    }
    private func persistActive() {
        do {
            if let active { defaults.set(try JSONEncoder().encode(active), forKey: "activeSession") }
            else { defaults.removeObject(forKey: "activeSession") }
        } catch { errorMessage = error.localizedDescription }
    }
    func start() {
        guard active == nil, preferences.durationMinutes > 0 else { return }
        now = Date(); active = ActiveSession(minutes: preferences.durationMinutes, now: now)
        persistActive(); startAudioAndAlert()
        if preferences.startBell { do { try audio.previewSound("bell", volume: preferences.endingVolume) } catch { errorMessage = error.localizedDescription } }
    }
    func pause() {
        guard active != nil, active?.isPaused == false else { return }
        tick(); guard active != nil else { return }
        active?.pause(at: Date()); persistActive(); cancelNotifications(); audio.stop()
    }
    func resume() {
        guard active?.isPaused == true else { return }
        now = Date(); active?.resume(at: now); persistActive(); startAudioAndAlert()
    }
    func discard() { cancelNotifications(); audio.stop(); active = nil; persistActive() }
    func saveEarly() { finish(at: Date()) }
    func tick(playSound: Bool = true) {
        let instant = Date()
        // Avoid invalidating the journal four times a second when no timer is running.
        guard active != nil else {
            if Day.key(now) != Day.key(instant) { now = instant }
            return
        }
        now = instant
        guard var session = active, !session.isPaused, !session.hasHandledPlannedEnd,
              session.elapsed(at: now) >= session.targetSeconds else { return }
        if playSound, foreground, !audio.scheduledEnding {
            do { try audio.playEnding(preferences) }
            catch { errorMessage = error.localizedDescription }
        }
        session.plannedEndHandled = true
        active = session
        persistActive()
    }
    func recover() {
        now = Date()
        LegacyAlarmCleanup.cancelAll()
        guard let active else { notifications.cancelFinish(); return }
        if sessions.contains(where: { $0.id == active.id }) {
            self.active = nil; persistActive(); cancelNotifications(); return
        }
        tick(playSound: false)
        if self.active?.isPaused == false { startAudioAndAlert() }
    }
    private func finish(at date: Date) {
        guard let active else { return }
        let record = active.record(at: date)
        guard record.seconds >= 1 else { discard(); return }
        do {
            // Persist first. The active ID remains recoverable if saving fails or the process exits.
            if !sessions.contains(where: { $0.id == record.id }) { try persistence.save(record) }
            audio.stop(); cancelNotifications()
            self.active = nil; persistActive(); reload()
            completed = sessions.first(where: { $0.id == record.id })
        } catch {
            audio.stop(); cancelNotifications()
            errorMessage = "Your session hasn’t been saved yet. Your timer is retained; tap Save again. \(error.localizedDescription)"
        }
    }
    private func startAudioAndAlert() {
        guard let active, let deadline = active.deadline else { return }
        do { try audio.start(preferences, remaining: max(0, deadline.timeIntervalSinceNow)) }
        catch { errorMessage = error.localizedDescription }
        let sessionPreferences = preferences
        let audioHandlesSound = audio.scheduledEnding
        let sessionID = active.id
        let previousTask = notificationTask
        previousTask?.cancel()
        notificationTask = Task {
            // Serialize replacements so a cancelled request cannot remove its successor.
            await previousTask?.value
            guard !Task.isCancelled, self.active?.id == sessionID, self.active?.isPaused == false else { return }
            do { try await notifications.scheduleFinish(deadline: deadline, preferences: sessionPreferences, audioHandlesSound: audioHandlesSound) }
            catch {
                if !Task.isCancelled, sessionPreferences.backgroundAlerts {
                    errorMessage = "The planned-time alert couldn’t be scheduled. \(error.localizedDescription)"
                }
            }
            if Task.isCancelled { notifications.cancelFinish() }
        }
    }
    private func cancelNotifications() {
        notificationTask?.cancel(); notificationTask = nil; notifications.cancelFinish()
    }
    func saveSession(_ record: SessionRecord) -> Bool {
        guard record.completedAt <= Date(), record.dayKey <= Day.key(Date()), record.seconds >= 1,
              record.seconds.isFinite, record.reflection.count <= 10_000 else { errorMessage = "Choose a past or present date and a valid duration."; return false }
        do { try persistence.save(record); reload(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult func deleteSession(_ id: UUID) -> Bool {
        do { try persistence.delete(id); reload(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func setGoal(_ minutes: Int) {
        do { try persistence.saveGoal(GoalRecord(effectiveDay: Day.key(Date()), minutes: minutes)); reload() }
        catch { errorMessage = error.localizedDescription }
    }
    func requestPermission(_ purpose: PermissionPurpose) async {
        do {
            let allowed = try await notifications.request()
            guard allowed else { errorMessage = "Notifications are off. You can enable them in iPhone Settings → Notifications → Pause."; return }
            updatePreferences { if purpose == .completion { $0.backgroundAlerts = true } else { $0.reminderEnabled = true } }
            if purpose == .completion, active?.isPaused == false { startAudioAndAlert() }
            await updateReminder()
        } catch { errorMessage = error.localizedDescription }
    }
    func updateReminder() async {
        do { try await notifications.updateReminder(preferences) } catch { errorMessage = error.localizedDescription }
    }
    func makeBackup() throws -> Data { try Backup(sessions: sessions, goals: goals, preferences: preferences).data() }
    func importBackup(_ data: Data) throws {
        let backup = try Backup.decode(data)
        try persistence.merge(backup)
        updatePreferences { $0 = backup.preferences }
        reload()
        Task { await updateReminder() }
    }
}
