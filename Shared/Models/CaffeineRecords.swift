import Foundation
import SwiftData

@Model
final class CachedCaffeineDose {
    @Attribute(.unique) var id: String
    var date: Date
    var milligrams: Double
    var sourceBundleID: String
    var sourceName: String
    var isOurs: Bool

    init(
        id: String,
        date: Date,
        milligrams: Double,
        sourceBundleID: String,
        sourceName: String,
        isOurs: Bool
    ) {
        self.id = id
        self.date = date
        self.milligrams = milligrams
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.isOurs = isOurs
    }
}

@Model
final class DailyCaffeineRecord {
    @Attribute(.unique) var dateString: String
    var date: Date
    var milligrams: Double
    var estimatedAtBedtime: Double
    var lastUpdated: Date

    init(date: Date, milligrams: Double = 0, estimatedAtBedtime: Double = 0) {
        let normalized = DateHelpers.startOfDay(date)
        self.dateString = DateHelpers.dayKey(for: normalized)
        self.date = normalized
        self.milligrams = milligrams
        self.estimatedAtBedtime = estimatedAtBedtime
        self.lastUpdated = .now
    }
}

@Model
final class LocalCaffeineEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var milligrams: Double
    var healthKitUUID: String?

    init(id: UUID = UUID(), date: Date = .now, milligrams: Double, healthKitUUID: String? = nil) {
        self.id = id
        self.date = date
        self.milligrams = milligrams
        self.healthKitUUID = healthKitUUID
    }
}
