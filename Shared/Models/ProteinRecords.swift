import Foundation
import SwiftData

/// Read-through cache of a day's reconciled protein total.
///
/// HealthKit is the source of truth (`docs/plan.md` §4); this exists only
/// because widgets and complications cannot query HealthKit. The app writes a
/// row whenever it reconciles, and the extensions read it.
@Model
final class DailyProteinRecord {
    /// "yyyy-MM-dd" — a string key rather than a `Date` so uniqueness survives
    /// timezone changes and DST without a predicate that spans midnight.
    @Attribute(.unique) var dateString: String
    var date: Date
    var proteinGrams: Double
    /// Snapshotted with the day so history rows show the target that was in
    /// force then, not whatever the target happens to be today.
    var targetGrams: Double
    var lastUpdated: Date

    init(date: Date, proteinGrams: Double = 0, targetGrams: Double = 0) {
        let normalized = DateHelpers.startOfDay(date)
        self.dateString = DateHelpers.dayKey(for: normalized)
        self.date = normalized
        self.proteinGrams = proteinGrams
        self.targetGrams = targetGrams
        self.lastUpdated = .now
    }

    static func key(for date: Date) -> String {
        DateHelpers.dayKey(for: date)
    }
}

/// An entry that could not be written to HealthKit.
///
/// Write authorization is a real user state, not a theoretical one: HealthKit
/// reports share denial honestly, and an app whose entire job is logging grams
/// cannot simply stop working because the user tapped the wrong toggle. These
/// rows are summed alongside the HealthKit samples, and are retried the next
/// time authorization allows it.
@Model
final class LocalProteinEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var grams: Double
    /// Set once the entry has been successfully mirrored into HealthKit, after
    /// which it must stop contributing to the sum or the grams count twice.
    var healthKitUUID: String?

    init(id: UUID = UUID(), date: Date = .now, grams: Double, healthKitUUID: String? = nil) {
        self.id = id
        self.date = date
        self.grams = grams
        self.healthKitUUID = healthKitUUID
    }

    /// Local-only entries are the ones the reconciliation has to add; mirrored
    /// ones already arrive through the HealthKit query.
    var countsTowardTotal: Bool { healthKitUUID == nil }
}
