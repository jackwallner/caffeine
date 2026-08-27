import Foundation
import SwiftData

@MainActor
final class CaffeineLogService: ObservableObject {
    static let shared = CaffeineLogService()

    struct LoggedEntry: Equatable {
        let milligrams: Double
        let date: Date
        let healthKitUUID: UUID?
        let localID: UUID?
    }

    @Published private(set) var lastEntry: LoggedEntry?
    @Published private(set) var lastWriteFellBack = false

    private init() {}

    @discardableResult
    func log(milligrams: Double, at date: Date = .now) async -> Bool {
        guard milligrams > 0 else { return false }
        if let uuid = await HealthKitService.shared.saveCaffeine(milligrams: milligrams, at: date) {
            lastEntry = LoggedEntry(milligrams: milligrams, date: date, healthKitUUID: uuid, localID: nil)
            lastWriteFellBack = false
        } else {
            let entry = LocalCaffeineEntry(date: date, milligrams: milligrams)
            let context = DataService.sharedModelContainer.mainContext
            context.insert(entry)
            try? context.save()
            lastEntry = LoggedEntry(milligrams: milligrams, date: date, healthKitUUID: nil, localID: entry.id)
            lastWriteFellBack = true
        }
        await HealthKitService.shared.refreshCache()
        return true
    }

    @discardableResult
    func undoLast() async -> Bool {
        guard let entry = lastEntry else { return false }
        let removed: Bool
        if let uuid = entry.healthKitUUID {
            removed = await HealthKitService.shared.deleteCaffeine(uuid: uuid)
        } else if let id = entry.localID {
            let context = DataService.sharedModelContainer.mainContext
            let descriptor = FetchDescriptor<LocalCaffeineEntry>(predicate: #Predicate { $0.id == id })
            if let row = try? context.fetch(descriptor).first {
                context.delete(row)
                try? context.save()
                removed = true
            } else {
                removed = false
            }
        } else {
            removed = false
        }
        if removed {
            lastEntry = nil
            await HealthKitService.shared.refreshCache()
        }
        return removed
    }

    @discardableResult
    func delete(sample: CaffeineSample) async -> Bool {
        guard sample.isOurs, let id = UUID(uuidString: sample.id) else { return false }
        let removed: Bool
        if sample.isLocalOnly {
            let context = DataService.sharedModelContainer.mainContext
            let descriptor = FetchDescriptor<LocalCaffeineEntry>(predicate: #Predicate { $0.id == id })
            if let row = try? context.fetch(descriptor).first {
                context.delete(row)
                try? context.save()
                removed = true
            } else {
                removed = false
            }
        } else {
            removed = await HealthKitService.shared.deleteCaffeine(uuid: id)
        }
        if removed { await HealthKitService.shared.refreshCache() }
        return removed
    }

    func retryPendingLocalEntries() async {
        let health = HealthKitService.shared
        health.refreshWriteAuthorization()
        guard health.canWrite else { return }
        let context = DataService.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<LocalCaffeineEntry>(predicate: #Predicate { $0.healthKitUUID == nil })
        for entry in (try? context.fetch(descriptor)) ?? [] {
            if let uuid = await health.saveCaffeine(milligrams: entry.milligrams, at: entry.date) {
                entry.healthKitUUID = uuid.uuidString
            }
        }
        try? context.save()
        lastWriteFellBack = false
        await health.refreshCache()
    }
}
