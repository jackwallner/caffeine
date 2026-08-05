import Foundation
import HealthKit
import os
import SwiftData
import WidgetKit
#if os(watchOS)
import WatchKit
#endif

private let healthKitLogger = Logger(subsystem: "com.jackwallner.protein", category: "HealthKit")

/// Reads, writes, and reconciles `dietaryProtein`.
///
/// The shape follows Total Calories' dietary layer, with one deliberate
/// departure: totals come from an `HKSampleQuery` grouped by source rather than
/// a statistics collection. A statistics sum cannot answer "which app wrote
/// this, and when", and both of those are product surface here — the source
/// picker and the freshness rows are the moat (`docs/positioning.md` §4).
@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    /// True once we believe reads are allowed. Apple never reports read
    /// authorization, so this tracks "the permission sheet has been answered",
    /// not "the user said yes".
    @Published var isAuthorized: Bool
    /// Write authorization, which HealthKit *does* report honestly.
    @Published private(set) var canWrite = false
    @Published private(set) var lastError: String?

    /// Today's samples from every source, before the selection is applied. The
    /// Sources screen needs the excluded ones too, so filtering happens at the
    /// reconciliation step and not in the query.
    @Published private(set) var todaySamples: [ProteinSample] = []
    @Published private(set) var lastRefreshed: Date?

    private let proteinType = HKQuantityType(.dietaryProtein)
    private let bodyMassType = HKQuantityType(.bodyMass)

    private init() {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            canWrite = true
        } else {
            isAuthorized = false
            Task { await self.synchronizeAuthorization() }
        }
    }

    // MARK: - Authorization

    /// Requests read *and* write for dietary protein in one sheet. Unlike the
    /// read-only apps in the fleet this one writes, so splitting the request
    /// would show the user two prompts for one feature.
    func requestAuthorization() async throws {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            canWrite = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [proteinType], read: [proteinType])
            isAuthorized = true
            refreshWriteAuthorization()
            enableBackgroundDelivery()
            healthKitLogger.info("Protein authorization request completed, canWrite=\(self.canWrite, privacy: .public)")
        } catch {
            healthKitLogger.error("Protein authorization request failed: \(String(describing: error), privacy: .public)")
            lastError = "Apple Health access could not be set up."
            throw error
        }
    }

    /// Body weight is requested separately and only when the user asks for a
    /// suggested target. Folding a new read type into an existing request can
    /// silently suppress the permission sheet, and body weight is not needed for
    /// the app to work at all.
    func requestBodyMassAuthorization() async throws {
        if ScreenshotConfig.isEnabled { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: [bodyMassType])
    }

    func refreshWriteAuthorization() {
        if ScreenshotConfig.isEnabled {
            canWrite = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            canWrite = false
            return
        }
        canWrite = store.authorizationStatus(for: proteinType) == .sharingAuthorized
    }

    /// `getRequestStatus` only reports whether the permission sheet still needs
    /// showing — never the user's answer for reads. So: ask when it says to ask,
    /// otherwise assume we may read and let an empty result speak for itself.
    func synchronizeAuthorization() async {
        if ScreenshotConfig.isEnabled {
            isAuthorized = true
            canWrite = true
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        refreshWriteAuthorization()
        guard let status = await authorizationRequestStatus() else { return }
        switch status {
        case .shouldRequest:
            break // Onboarding owns the first prompt; never surprise the user here.
        case .unnecessary:
            isAuthorized = true
            enableBackgroundDelivery()
        case .unknown:
            break
        @unknown default:
            isAuthorized = true
        }
    }

    func authorizationRequestStatus() async -> HKAuthorizationRequestStatus? {
        if ScreenshotConfig.isEnabled { return .unnecessary }
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [proteinType], read: [proteinType]) { status, error in
                if let error {
                    healthKitLogger.error("Request-status lookup failed: \(String(describing: error), privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Reads

    /// Every dietary-protein sample in the window, flattened to the fields
    /// reconciliation needs. Samples are mapped inside the query callback
    /// because `HKSample` is not `Sendable`.
    func fetchSamples(from start: Date, to end: Date) async throws -> [ProteinSample] {
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
                sampleType: proteinType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    let nsError = error as NSError
                    // "Authorization not determined" is the normal answer on a
                    // fresh install and must not paint an error state.
                    if nsError.domain == HKError.errorDomain,
                       nsError.code == HKError.errorAuthorizationNotDetermined.rawValue {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }
                let mapped: [ProteinSample] = (samples as? [HKQuantitySample] ?? []).map { sample in
                    let source = sample.sourceRevision.source
                    return ProteinSample(
                        id: sample.uuid.uuidString,
                        sourceBundleID: source.bundleIdentifier,
                        sourceName: source.name,
                        grams: sample.quantity.doubleValue(for: .gram()),
                        endDate: sample.endDate,
                        isOurs: proteinOwnSourceBundleIDs.contains(source.bundleIdentifier)
                    )
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    func fetchTodaySamples() async throws -> [ProteinSample] {
        try await fetchSamples(from: DateHelpers.startOfDay(), to: DateHelpers.endOfDay())
    }

    /// Most recent body mass in kilograms, for the suggested target only.
    func fetchBodyMassKilograms() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(sampleType: bodyMassType, predicate: nil, limit: 1, sortDescriptors: sort) { _, samples, _ in
                guard let sample = (samples as? [HKQuantitySample])?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)))
            }
            store.execute(query)
        }
    }

    // MARK: - Writes

    /// Saves grams as a real `dietaryProtein` sample so every other app on the
    /// phone can read them, and returns the sample UUID for undo.
    ///
    /// Returns `nil` when HealthKit refused the write. The caller falls back to
    /// a local entry rather than dropping the user's grams — see
    /// `ProteinLogService`.
    @discardableResult
    func saveProtein(grams: Double, at date: Date = .now) async -> UUID? {
        guard grams > 0 else { return nil }
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        refreshWriteAuthorization()
        guard canWrite else {
            healthKitLogger.info("Protein write skipped: sharing not authorized")
            return nil
        }
        let sample = HKQuantitySample(
            type: proteinType,
            quantity: HKQuantity(unit: .gram(), doubleValue: grams),
            start: date,
            end: date
        )
        do {
            try await store.save(sample)
            return sample.uuid
        } catch {
            healthKitLogger.error("Protein write failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Deletes one of our own samples. HealthKit only permits deleting objects
    /// the calling app saved, which is exactly the guarantee undo needs.
    func deleteProtein(uuid: UUID) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let predicate = HKQuery.predicateForObject(with: uuid)
        let object: HKObject? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: proteinType, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples?.first)
            }
            store.execute(query)
        }
        guard let object else { return false }
        do {
            try await store.delete(object)
            return true
        } catch {
            healthKitLogger.error("Protein delete failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: - Background delivery

    private var pendingRefreshTask: Task<Void, Never>?
    private var observerInstalled = false

    func enableBackgroundDelivery() {
        if ScreenshotConfig.isEnabled { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard !observerInstalled else { return }
        observerInstalled = true

        store.enableBackgroundDelivery(for: proteinType, frequency: .hourly) { _, error in
            if let error {
                healthKitLogger.error("Background delivery error: \(String(describing: error), privacy: .public)")
            }
        }

        let query = HKObserverQuery(sampleType: proteinType, predicate: nil) { [weak self] _, completionHandler, error in
            // Call the completion handler immediately — watchOS kills the app if
            // this isn't called within 15 seconds.
            completionHandler()
            if let error {
                healthKitLogger.error("Observer query error: \(String(describing: error), privacy: .public)")
                return
            }
            #if os(watchOS)
            // Don't do heavy work in the observer callback on watchOS: the
            // CAROUSEL watchdog has a tight CPU budget. Schedule instead.
            Task { @MainActor in
                WKApplication.shared().scheduleBackgroundRefresh(
                    withPreferredDate: Date(timeIntervalSinceNow: 5),
                    userInfo: nil
                ) { _ in }
            }
            #else
            Task { @MainActor in
                // Debounce: a food logger writing a meal often lands several
                // samples at once.
                self?.pendingRefreshTask?.cancel()
                self?.pendingRefreshTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    await self?.refreshCache()
                }
            }
            #endif
        }
        store.execute(query)
    }

    // MARK: - Cache

    /// Re-reads today from HealthKit, reconciles it against the source
    /// selection and any local-only entries, and writes the day row the widgets
    /// and complications read.
    func refreshCache() async {
        do {
            let samples = try await fetchTodaySamples()
            todaySamples = samples
            lastRefreshed = .now
            lastError = nil

            let settings = GoalSettings.shared
            let localGrams = Self.pendingLocalGramsToday()
            let total = ProteinReconciliation.total(samples: samples, selection: settings.sourceSelection) + localGrams
            writeDayRecord(total: total, target: settings.targetGrams)

            if ProteinReconciliation.hasMetTarget(total: total, target: settings.targetGrams) {
                ReviewPromptTracker.recordTargetHit()
            }
        } catch {
            healthKitLogger.error("Cache refresh failed: \(String(describing: error), privacy: .public)")
            lastError = "Could not read protein from Apple Health."
        }
    }

    /// Daily totals for the history screen, reconciled the same way today is.
    func fetchHistory(days: Int) async throws -> [(date: Date, grams: Double)] {
        let start = DateHelpers.daysAgo(max(days - 1, 0))
        let samples = try await fetchSamples(from: start, to: DateHelpers.endOfDay())
        let selection = GoalSettings.shared.sourceSelection

        var buckets: [String: Double] = [:]
        for sample in samples where selection.includes(bundleID: sample.sourceBundleID, isOurs: sample.isOurs) {
            buckets[DateHelpers.dayKey(for: sample.endDate), default: 0] += max(sample.grams, 0)
        }
        // Local-only entries never reached HealthKit, so they have to be added
        // back or a write-denied user sees a history of zeros.
        for entry in Self.pendingLocalEntries(since: start) {
            buckets[DateHelpers.dayKey(for: entry.date), default: 0] += max(entry.grams, 0)
        }

        var results: [(date: Date, grams: Double)] = []
        var cursor = DateHelpers.startOfDay(start)
        let today = DateHelpers.startOfDay()
        while cursor <= today {
            results.append((date: cursor, grams: buckets[DateHelpers.dayKey(for: cursor)] ?? 0))
            guard let next = DateHelpers.gregorian.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return results
    }

    private func writeDayRecord(total: Double, target: Double) {
        let context = DataService.sharedModelContainer.mainContext
        let key = DailyProteinRecord.key(for: .now)
        let descriptor = FetchDescriptor<DailyProteinRecord>(predicate: #Predicate { $0.dateString == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.proteinGrams = total
            existing.targetGrams = target
            existing.lastUpdated = .now
        } else {
            context.insert(DailyProteinRecord(date: .now, proteinGrams: total, targetGrams: target))
        }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Local fallback entries

    /// Grams logged today that never reached HealthKit.
    static func pendingLocalGramsToday() -> Double {
        pendingLocalEntries(since: DateHelpers.startOfDay()).reduce(0) { $0 + max($1.grams, 0) }
    }

    static func pendingLocalEntries(since start: Date) -> [LocalProteinEntry] {
        let context = DataService.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<LocalProteinEntry>(
            predicate: #Predicate { $0.date >= start && $0.healthKitUUID == nil }
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
