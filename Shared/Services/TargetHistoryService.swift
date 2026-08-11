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
/// Both answers are therefore writes. Keeping the past means materializing the
/// old target onto the days that had none; applying it retroactively means
/// rewriting the days that had one.
@MainActor
enum TargetHistoryService {
    /// How far back either answer reaches. The Protein+ tab compares the last
    /// 30 days against the 30 before them, which is the deepest window anything
    /// in the app reads.
    static let windowDays = 60

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

    /// Keeps every past day judged against `previousTarget`.
    ///
    /// Days that already carry a target are left exactly as they are — they may
    /// hold an older number still, and this is not the moment to flatten that.
    /// Days with no row get one, which is what stops them drifting to whatever
    /// the target becomes next.
    static func freezePastDays(
        at previousTarget: Double,
        context: ModelContext = DataService.sharedModelContainer.mainContext
    ) {
        let today = DateHelpers.startOfDay()
        let start = DateHelpers.daysAgo(windowDays)
        let existing = Set(fetchRows(since: start, context: context).map(\.dateString))

        var cursor = start
        while cursor < today {
            let key = DateHelpers.dayKey(for: cursor)
            if !existing.contains(key) {
                // proteinGrams stays zero on purpose: for a past day only the
                // target is ever read back, and the grams come from HealthKit
                // every time history is drawn.
                context.insert(DailyProteinRecord(date: cursor, proteinGrams: 0, targetGrams: previousTarget))
            }
            guard let next = DateHelpers.gregorian.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        try? context.save()
    }

    /// Re-judges every past day against `target`.
    ///
    /// Stored rows are rewritten; days with no row need no work, because the
    /// history fallback already reads the current target for them.
    static func applyToPastDays(
        _ target: Double,
        context: ModelContext = DataService.sharedModelContainer.mainContext
    ) {
        let today = DateHelpers.startOfDay()
        for row in fetchRows(since: DateHelpers.daysAgo(windowDays), context: context) where row.date < today {
            row.targetGrams = target
            row.lastUpdated = .now
        }
        try? context.save()
    }

    private static func fetchRows(since start: Date, context: ModelContext) -> [DailyProteinRecord] {
        let descriptor = FetchDescriptor<DailyProteinRecord>(
            predicate: #Predicate { $0.date >= start }
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
