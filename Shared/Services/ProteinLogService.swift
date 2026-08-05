import Foundation
import os
import SwiftData
import WidgetKit

private let logServiceLogger = Logger(subsystem: "com.jackwallner.protein", category: "Log")

/// Adding, undoing, and rescuing grams.
///
/// Every entry tries HealthKit first, because that is what makes a wrist tap
/// show up on the phone with no queue of our own. When HealthKit refuses the
/// write — a real user state, since share authorization can be denied outright
/// — the grams land in a local row instead and are summed alongside the
/// HealthKit samples. Nothing the user typed is ever dropped on the floor.
@MainActor
final class ProteinLogService: ObservableObject {
    static let shared = ProteinLogService()

    /// The most recent entry from this device, so undo has something to remove.
    /// Session-scoped on purpose: undo is a "that was a mistake" affordance for
    /// the tap you just made, not an edit history.
    struct LoggedEntry: Equatable {
        let grams: Double
        let date: Date
        let healthKitUUID: UUID?
        let localID: UUID?
    }

    @Published private(set) var lastEntry: LoggedEntry?
    /// Set when an entry had to fall back to local storage, so the UI can say so
    /// once rather than silently diverging from Apple Health.
    @Published private(set) var lastWriteFellBack = false

    private init() {}

    /// Logs grams and refreshes everything downstream. Returns false only when
    /// the grams were rejected outright (non-positive).
    @discardableResult
    func log(grams: Double, at date: Date = .now) async -> Bool {
        guard grams > 0 else { return false }
        let health = HealthKitService.shared

        if let uuid = await health.saveProtein(grams: grams, at: date) {
            lastEntry = LoggedEntry(grams: grams, date: date, healthKitUUID: uuid, localID: nil)
            lastWriteFellBack = false
        } else {
            let entry = LocalProteinEntry(date: date, grams: grams)
            let context = DataService.sharedModelContainer.mainContext
            context.insert(entry)
            try? context.save()
            lastEntry = LoggedEntry(grams: grams, date: date, healthKitUUID: nil, localID: entry.id)
            lastWriteFellBack = true
            logServiceLogger.info("Logged \(grams, privacy: .public)g locally; HealthKit write unavailable")
        }

        await health.refreshCache()
        return true
    }

    /// Removes the entry this device logged most recently.
    @discardableResult
    func undoLast() async -> Bool {
        guard let entry = lastEntry else { return false }
        var removed = false

        if let uuid = entry.healthKitUUID {
            removed = await HealthKitService.shared.deleteProtein(uuid: uuid)
        } else if let localID = entry.localID {
            let context = DataService.sharedModelContainer.mainContext
            let descriptor = FetchDescriptor<LocalProteinEntry>(predicate: #Predicate { $0.id == localID })
            if let row = try? context.fetch(descriptor).first {
                context.delete(row)
                try? context.save()
                removed = true
            }
        }

        if removed {
            lastEntry = nil
            await HealthKitService.shared.refreshCache()
        }
        return removed
    }

    /// Pushes anything stranded locally into HealthKit once the user grants
    /// write access. The row is kept and stamped rather than deleted, so the
    /// grams stop being counted twice while the provenance survives.
    func retryPendingLocalEntries() async {
        let health = HealthKitService.shared
        health.refreshWriteAuthorization()
        guard health.canWrite else { return }

        let context = DataService.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<LocalProteinEntry>(predicate: #Predicate { $0.healthKitUUID == nil })
        let pending = (try? context.fetch(descriptor)) ?? []
        guard !pending.isEmpty else { return }

        var migrated = 0
        for entry in pending {
            if let uuid = await health.saveProtein(grams: entry.grams, at: entry.date) {
                entry.healthKitUUID = uuid.uuidString
                migrated += 1
            }
        }
        if migrated > 0 {
            try? context.save()
            lastWriteFellBack = false
            logServiceLogger.info("Migrated \(migrated, privacy: .public) local entries into Apple Health")
            await health.refreshCache()
        }
    }
}
