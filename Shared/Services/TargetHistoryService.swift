import Foundation
import SwiftData

/// What happens to yesterday when you change today's target.
///
/// History rows print the target that was in force on the day (`DailyProteinRecord.targetGrams`),
/// but a day the app never reconciled has no row, and `fetchHistory` falls back
/// to the current target for those. So doing nothing is not neutral: raising the
/// target silently re-judges every past day against the new number, and a week
/// of green days can turn red without the user touching history.
///
/// Both answers are therefore writes. Keeping the past means recording what the
/// target used to be; applying it retroactively means erasing that record and
/// rewriting the days that had one.
///
/// The record is a **change log**, not a row per day. Protein+ history has no
/// window any more, so materializing the old target onto every past day would
/// mean inserting a row for every day since install on every target change —
/// thousands of writes to answer a question that four numbers can answer.
/// `target(on:)` resolves any day, however old, from the handful of entries.
@MainActor
enum TargetHistoryService {
    /// "From this day forward, the target was N." Entries are kept sorted by
    /// date, one per day the target moved.
    struct TargetChange: Codable, Equatable {
        let date: Date
        let targetGrams: Double
    }

    nonisolated private static let logKey = "targetChangeLog"

    /// Nonisolated so the log can be read from `fetchHistory` and from the
    /// widget processes without hopping to the main actor. It is a plist read;
    /// there is nothing here to serialize.
    nonisolated static func defaultStore() -> UserDefaults {
        UserDefaults(suiteName: proteinAppGroupID) ?? .standard
    }

    // MARK: - Reading

    nonisolated static func changeLog(store: UserDefaults = defaultStore()) -> [TargetChange] {
        guard let data = store.data(forKey: logKey),
              let decoded = try? JSONDecoder().decode([TargetChange].self, from: data) else { return [] }
        return decoded.sorted { $0.date < $1.date }
    }

    /// The target that was in force on `date`, or nil when the log has nothing
    /// to say about a day that old. Nil is the honest answer: the caller falls
    /// back to the live target, which is the same behaviour a user who never
    /// changed their target has always had.
    nonisolated static func target(on date: Date, store: UserDefaults = defaultStore()) -> Double? {
        let day = DateHelpers.startOfDay(date)
        var answer: Double?
        for change in changeLog(store: store) where DateHelpers.startOfDay(change.date) <= day {
            answer = change.targetGrams
        }
        return answer
    }

    /// True when there is a past day whose verdict a target change would move.
    /// Nothing to ask about on a fresh install, so nothing is asked.
    static func hasPastDays(context: ModelContext = DataService.sharedModelContainer.mainContext) -> Bool {
        let today = DateHelpers.startOfDay()
        var descriptor = FetchDescriptor<DailyProteinRecord>(
            predicate: #Predicate { $0.date < today }
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
    }

    // MARK: - Writing

    /// Keeps every past day judged against `previousTarget`, and records that
    /// `newTarget` takes over from today.
    ///
    /// Days that already carry a stored target are left exactly as they are —
    /// they may hold an older number still, and this is not the moment to
    /// flatten that. Every other past day is answered by the log.
    static func freezePastDays(
        from previousTarget: Double,
        to newTarget: Double,
        store: UserDefaults = defaultStore()
    ) {
        let today = DateHelpers.startOfDay()
        var log = changeLog(store: store)

        // An empty log means nothing has ever recorded what the target used to
        // be, so the target being replaced is the one that has been in force
        // since install — all the way back, not merely since the last change.
        if log.isEmpty {
            log.append(TargetChange(date: .distantPast, targetGrams: previousTarget))
        }

        // A second change on the same day replaces the first: the target moved
        // twice before midnight, and only the last value was ever the day's.
        log.removeAll { DateHelpers.isSameDay($0.date, today) }
        log.append(TargetChange(date: today, targetGrams: newTarget))
        write(log, store: store)
    }

    /// Re-judges every past day against `target`.
    ///
    /// The log collapses to a single entry covering all of time, and the stored
    /// rows — which outrank it — are rewritten to match. Unbounded on purpose:
    /// history has no window, so neither can this.
    static func applyToPastDays(
        _ target: Double,
        context: ModelContext = DataService.sharedModelContainer.mainContext,
        store: UserDefaults = defaultStore()
    ) {
        write([TargetChange(date: .distantPast, targetGrams: target)], store: store)

        let today = DateHelpers.startOfDay()
        for row in allRows(context: context) where row.date < today {
            row.targetGrams = target
            row.lastUpdated = .now
        }
        try? context.save()
    }

    /// Test seam. Never called in the app: the log is only ever appended to.
    nonisolated static func resetLog(store: UserDefaults = defaultStore()) {
        store.removeObject(forKey: logKey)
    }

    nonisolated private static func write(_ log: [TargetChange], store: UserDefaults) {
        guard let data = try? JSONEncoder().encode(log.sorted(by: { $0.date < $1.date })) else { return }
        store.set(data, forKey: logKey)
    }

    private static func allRows(context: ModelContext) -> [DailyProteinRecord] {
        (try? context.fetch(FetchDescriptor<DailyProteinRecord>())) ?? []
    }
}
