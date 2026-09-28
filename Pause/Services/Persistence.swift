import Foundation
import SwiftData

@Model final class StoredSession {
    @Attribute(.unique) var id: UUID
    var completedAt: Date
    var dayKey: String
    var seconds: Double
    var reflection: String
    var source: String
    var updatedAt: Date
    init(_ record: SessionRecord) {
        id = record.id; completedAt = record.completedAt; dayKey = record.dayKey; seconds = record.seconds
        reflection = record.reflection; source = record.source; updatedAt = record.updatedAt
    }
    var record: SessionRecord { SessionRecord(id: id, completedAt: completedAt, dayKey: dayKey, seconds: seconds, reflection: reflection, source: source, updatedAt: updatedAt) }
    func update(_ r: SessionRecord) {
        completedAt = r.completedAt; dayKey = r.dayKey; seconds = r.seconds; reflection = r.reflection; source = r.source; updatedAt = r.updatedAt
    }
}
@Model final class StoredGoal {
    @Attribute(.unique) var id: UUID
    var effectiveDay: String
    var minutes: Int
    var updatedAt: Date
    init(_ r: GoalRecord) { id = r.id; effectiveDay = r.effectiveDay; minutes = r.minutes; updatedAt = r.updatedAt }
    var record: GoalRecord { GoalRecord(id: id, effectiveDay: effectiveDay, minutes: minutes, updatedAt: updatedAt) }
}

@MainActor final class Persistence {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    init(inMemory: Bool = false, storeURL: URL? = nil) throws {
        let schema = Schema([StoredSession.self, StoredGoal.self])
        let config: ModelConfiguration
        if let storeURL { config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none) }
        else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        container = try ModelContainer(for: schema, configurations: [config])
        context.autosaveEnabled = false
        if try context.fetch(FetchDescriptor<StoredGoal>()).isEmpty {
            context.insert(StoredGoal(.baseline)); try context.save()
        }
    }
    func sessions() throws -> [SessionRecord] { try context.fetch(FetchDescriptor<StoredSession>()).map(\.record).sorted { $0.completedAt > $1.completedAt } }
    func goals() throws -> [GoalRecord] { try context.fetch(FetchDescriptor<StoredGoal>()).map(\.record) }
    func save(_ record: SessionRecord) throws {
        do {
            let id = record.id
            if let stored = try context.fetch(FetchDescriptor<StoredSession>(predicate: #Predicate { $0.id == id })).first { stored.update(record) }
            else { context.insert(StoredSession(record)) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    func delete(_ id: UUID) throws {
        do {
            for item in try context.fetch(FetchDescriptor<StoredSession>(predicate: #Predicate { $0.id == id })) { context.delete(item) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    func saveGoal(_ record: GoalRecord) throws {
        do {
            let day = record.effectiveDay
            let items = try context.fetch(FetchDescriptor<StoredGoal>(predicate: #Predicate { $0.effectiveDay == day }))
            // Preserve the ID when changing this day's goal record.
            if let item = items.first { item.minutes = record.minutes; item.updatedAt = record.updatedAt }
            else { context.insert(StoredGoal(record)) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    func merge(_ backup: Backup) throws {
        do {
            let existingSessions = try context.fetch(FetchDescriptor<StoredSession>())
            let byID = Dictionary(uniqueKeysWithValues: existingSessions.map { ($0.id, $0) })
            for record in backup.mergedSessions(with: existingSessions.map(\.record)) {
                if let stored = byID[record.id] { stored.update(record) } else { context.insert(StoredSession(record)) }
            }
            let existingGoals = try context.fetch(FetchDescriptor<StoredGoal>())
            let goalIDs = Dictionary(uniqueKeysWithValues: existingGoals.map { ($0.id, $0) })
            for record in backup.mergedGoals(with: existingGoals.map(\.record)) {
                if let stored = goalIDs[record.id] { stored.effectiveDay = record.effectiveDay; stored.minutes = record.minutes; stored.updatedAt = record.updatedAt }
                else { context.insert(StoredGoal(record)) }
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}
