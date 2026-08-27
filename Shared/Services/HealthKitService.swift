import Foundation
import HealthKit
import os
import SwiftData
import WidgetKit

enum HealthReadState {
    case notDetermined
    case receiving
    case noData
}

@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()
    static let lookbackHours = 48.0
    static let maximumHistoryDays = 3650

    @Published var isAuthorized = false
    @Published private(set) var canWrite = false
    @Published private(set) var recentSamples: [CaffeineSample] = []
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var hasEverReadSamples: Bool

    private let store = HKHealthStore()
    private let caffeineType = HKQuantityType(.dietaryCaffeine)
    private let logger = Logger(subsystem: "com.jackwallner.caffeine", category: "HealthKit")
    private let defaults = UserDefaults(suiteName: caffeineAppGroupID) ?? .standard
    private var observerInstalled = false
    private static let hasEverReadSamplesKey = "hasEverReadCaffeineSamples"

    var readState: HealthReadState {
        guard isAuthorized else { return .notDetermined }
        return hasEverReadSamples ? .receiving : .noData
    }

    private init() {
        hasEverReadSamples = defaults.bool(forKey: Self.hasEverReadSamplesKey)
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            canWrite = true
            hasEverReadSamples = true
        }
    }

    func requestAuthorization() async throws {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            canWrite = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [caffeineType], read: [caffeineType])
        isAuthorized = true
        refreshWriteAuthorization()
        enableBackgroundDelivery()
    }

    func synchronizeAuthorization() async {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            canWrite = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        refreshWriteAuthorization()
        let status = await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [caffeineType], read: [caffeineType]) { value, _ in
                continuation.resume(returning: value)
            }
        }
        if status == .unnecessary {
            isAuthorized = true
            enableBackgroundDelivery()
        }
    }

    func refreshWriteAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            canWrite = false
            return
        }
        canWrite = store.authorizationStatus(for: caffeineType) == .sharingAuthorized
    }

    func fetchSamples(from start: Date, to end: Date) async throws -> [CaffeineSample] {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            return ScreenshotFixtures.samples(from: start, to: end)
        }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: caffeineType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    let value = error as NSError
                    if value.domain == HKError.errorDomain,
                       value.code == HKError.errorAuthorizationNotDetermined.rawValue {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let mapped = (samples as? [HKQuantitySample] ?? []).map { sample in
                    let source = sample.sourceRevision.source
                    return CaffeineSample(
                        id: sample.uuid.uuidString,
                        sourceBundleID: source.bundleIdentifier,
                        sourceName: source.name,
                        milligrams: sample.quantity.doubleValue(for: .gramUnit(with: .milli)),
                        endDate: sample.endDate,
                        isOurs: caffeineOwnSourceBundleIDs.contains(source.bundleIdentifier)
                    )
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    @discardableResult
    func saveCaffeine(milligrams: Double, at date: Date = .now) async -> UUID? {
        guard milligrams > 0, HKHealthStore.isHealthDataAvailable() else { return nil }
        refreshWriteAuthorization()
        guard canWrite else { return nil }
        let sample = HKQuantitySample(
            type: caffeineType,
            quantity: HKQuantity(unit: .gramUnit(with: .milli), doubleValue: milligrams),
            start: date,
            end: date
        )
        do {
            try await store.save(sample)
            return sample.uuid
        } catch {
            logger.error("Caffeine write failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func deleteCaffeine(uuid: UUID) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let predicate = HKQuery.predicateForObject(with: uuid)
        let object: HKObject? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: caffeineType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first)
            }
            store.execute(query)
        }
        guard let object else { return false }
        do {
            try await store.delete(object)
            return true
        } catch {
            return false
        }
    }

    func refreshCache(now: Date = .now) async {
        let start = now.addingTimeInterval(-Self.lookbackHours * 3600)
        do {
            let healthSamples = try await fetchSamples(from: start, to: now.addingTimeInterval(60))
            if !healthSamples.isEmpty {
                hasEverReadSamples = true
                defaults.set(true, forKey: Self.hasEverReadSamplesKey)
            }
            recentSamples = healthSamples + Self.pendingLocalSamples(since: start)
            lastRefreshed = now
            lastError = nil
            writeCache(now: now)
            #if os(iOS)
            if CaffeineSettings.shared.reminderEnabled {
                await NotificationService.scheduleBedtimePreview(
                    at: CaffeineSettings.shared.bedtimeDate,
                    estimatedMilligrams: bedtimeForecast.estimatedMilligrams
                )
            }
            #endif
        } catch {
            logger.error("Caffeine refresh failed: \(String(describing: error), privacy: .public)")
            lastError = "Caffeine data could not be read from Apple Health."
        }
    }

    var consumedToday: Double {
        CaffeineClearance.consumedToday(
            samples: recentSamples,
            selection: CaffeineSettings.shared.sourceSelection
        )
    }

    var remainingNow: Double {
        CaffeineClearance.remaining(
            samples: recentSamples,
            at: .now,
            selection: CaffeineSettings.shared.sourceSelection,
            halfLifeHours: CaffeineSettings.shared.halfLifeHours
        )
    }

    var bedtimeForecast: CaffeineForecast {
        CaffeineClearance.forecast(
            samples: recentSamples,
            at: CaffeineSettings.shared.bedtimeDate,
            selection: CaffeineSettings.shared.sourceSelection,
            halfLifeHours: CaffeineSettings.shared.halfLifeHours
        )
    }

    func fetchHistory(days: Int) async throws -> [CaffeineDaySummary] {
        #if DEBUG
        if ScreenshotConfig.isEnabled { return ScreenshotFixtures.history(days: days) }
        #endif
        let count = max(days, 1)
        let start = DateHelpers.daysAgo(count - 1)
        let samples = try await fetchSamples(from: start, to: DateHelpers.endOfDay())
        let selection = CaffeineSettings.shared.sourceSelection
        var result: [CaffeineDaySummary] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            let day = DateHelpers.daysAgo(offset)
            let dayStart = DateHelpers.startOfDay(day)
            let dayEnd = DateHelpers.endOfDay(day)
            let consumed = samples
                .filter { $0.endDate >= dayStart && $0.endDate < dayEnd }
                .filter { selection.includes(bundleID: $0.sourceBundleID, isOurs: $0.isOurs) }
                .reduce(0) { $0 + max($1.milligrams, 0) }
            let bedtime = CaffeineSettings.shared.bedtime(onOrAfter: dayStart)
            let forecast = CaffeineClearance.remaining(
                samples: samples,
                at: bedtime,
                selection: selection,
                halfLifeHours: CaffeineSettings.shared.halfLifeHours
            )
            result.append(CaffeineDaySummary(date: dayStart, milligrams: consumed, estimatedAtBedtime: forecast))
        }
        return result
    }

    private func writeCache(now: Date) {
        let context = DataService.sharedModelContainer.mainContext
        if let cached = try? context.fetch(FetchDescriptor<CachedCaffeineDose>()) {
            cached.forEach(context.delete)
        }
        for sample in recentSamples where CaffeineSettings.shared.sourceSelection.includes(
            bundleID: sample.sourceBundleID,
            isOurs: sample.isOurs
        ) {
            context.insert(CachedCaffeineDose(
                id: sample.id,
                date: sample.endDate,
                milligrams: sample.milligrams,
                sourceBundleID: sample.sourceBundleID,
                sourceName: sample.sourceName,
                isOurs: sample.isOurs
            ))
        }
        let key = DateHelpers.dayKey(for: now)
        let descriptor = FetchDescriptor<DailyCaffeineRecord>(predicate: #Predicate { $0.dateString == key })
        let record = (try? context.fetch(descriptor).first)
            ?? DailyCaffeineRecord(date: now)
        if record.modelContext == nil { context.insert(record) }
        record.milligrams = consumedToday
        record.estimatedAtBedtime = bedtimeForecast.estimatedMilligrams
        record.lastUpdated = now
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func enableBackgroundDelivery() {
        guard !observerInstalled, HKHealthStore.isHealthDataAvailable() else { return }
        observerInstalled = true
        store.enableBackgroundDelivery(for: caffeineType, frequency: .hourly) { _, _ in }
        let query = HKObserverQuery(sampleType: caffeineType, predicate: nil) { [weak self] _, completion, _ in
            completion()
            Task { @MainActor in await self?.refreshCache() }
        }
        store.execute(query)
    }

    static func pendingLocalEntries(since start: Date) -> [LocalCaffeineEntry] {
        let context = DataService.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<LocalCaffeineEntry>(
            predicate: #Predicate { $0.date >= start && $0.healthKitUUID == nil }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func pendingLocalSamples(since start: Date) -> [CaffeineSample] {
        pendingLocalEntries(since: start).map {
            CaffeineSample(
                id: $0.id.uuidString,
                sourceBundleID: caffeineOwnSourceBundleID,
                sourceName: "Caffeine",
                milligrams: $0.milligrams,
                endDate: $0.date,
                isOurs: true,
                isLocalOnly: true
            )
        }
    }
}
