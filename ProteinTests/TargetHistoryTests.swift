import SwiftData
import XCTest
@testable import Protein

/// What a target change does to the days behind it.
///
/// The trap this covers: a past day with no cached row falls back to the
/// *current* target when history is drawn, so leaving the past alone is not the
/// same as doing nothing. Keeping the past has to write.
///
/// Since history became unbounded, the second trap is depth: the answer has to
/// hold for a day two years back, not merely inside whatever window the app
/// used to draw.
@MainActor
final class TargetHistoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var store: UserDefaults!

    private static let suiteName = "TargetHistoryTests"

    override func setUpWithError() throws {
        let schema = Schema([DailyProteinRecord.self, LocalProteinEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        store = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        store.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: Self.suiteName)
        store = nil
        context = nil
        container = nil
    }

    @discardableResult
    private func insertRow(daysAgo: Int, target: Double, grams: Double = 0) -> DailyProteinRecord {
        let row = DailyProteinRecord(
            date: DateHelpers.daysAgo(daysAgo),
            proteinGrams: grams,
            targetGrams: target
        )
        context.insert(row)
        try? context.save()
        return row
    }

    private func rows() -> [DailyProteinRecord] {
        (try? context.fetch(FetchDescriptor<DailyProteinRecord>())) ?? []
    }

    private func row(daysAgo: Int) -> DailyProteinRecord? {
        let key = DateHelpers.dayKey(for: DateHelpers.daysAgo(daysAgo))
        return rows().first { $0.dateString == key }
    }

    /// The target history answer for a day, the way `fetchHistory` asks for it:
    /// the stored row first, then the log.
    private func resolvedTarget(daysAgo: Int, liveTarget: Double) -> Double {
        let stored = row(daysAgo: daysAgo)?.targetGrams ?? 0
        if stored > 0 { return stored }
        return TargetHistoryService.target(on: DateHelpers.daysAgo(daysAgo), store: store) ?? liveTarget
    }

    func testNothingToAskAboutOnAFreshInstall() {
        XCTAssertFalse(TargetHistoryService.hasPastDays(context: context))
    }

    /// Today's own row is not a past day: changing the target today is exactly
    /// what today's row is for.
    func testTodayAloneIsNotAPastDay() {
        insertRow(daysAgo: 0, target: 140)
        XCTAssertFalse(TargetHistoryService.hasPastDays(context: context))
        insertRow(daysAgo: 1, target: 140)
        XCTAssertTrue(TargetHistoryService.hasPastDays(context: context))
    }

    /// With no log at all, a past day inherits whatever the target becomes
    /// next. This is the drift the freeze exists to stop.
    func testWithNoLogAPastDayFallsThroughToTheLiveTarget() {
        XCTAssertNil(TargetHistoryService.target(on: DateHelpers.daysAgo(5), store: store))
        XCTAssertEqual(resolvedTarget(daysAgo: 5, liveTarget: 180), 180)
    }

    /// Keeping the past records the old target for every day behind today, at
    /// any depth, without writing a row per day.
    func testFreezingRecordsTheOldTargetAtAnyDepth() {
        insertRow(daysAgo: 3, target: 140, grams: 150)
        let before = rows().count
        TargetHistoryService.freezePastDays(from: 140, to: 180, store: store)

        XCTAssertEqual(resolvedTarget(daysAgo: 1, liveTarget: 180), 140)
        XCTAssertEqual(resolvedTarget(daysAgo: 90, liveTarget: 180), 140)
        XCTAssertEqual(resolvedTarget(daysAgo: 800, liveTarget: 180), 140)
        // The whole point of the log: four numbers, not eight hundred rows.
        XCTAssertEqual(rows().count, before)
    }

    /// A day that already carries a target may carry an older one still, and
    /// freezing is not the moment to flatten that.
    func testFreezingLeavesDaysThatAlreadyCarryATargetAlone() {
        insertRow(daysAgo: 2, target: 100, grams: 120)
        TargetHistoryService.freezePastDays(from: 140, to: 180, store: store)
        XCTAssertEqual(row(daysAgo: 2)?.targetGrams, 100)
        XCTAssertEqual(resolvedTarget(daysAgo: 2, liveTarget: 180), 100)
    }

    func testFreezingDoesNotTouchToday() {
        insertRow(daysAgo: 0, target: 160, grams: 40)
        TargetHistoryService.freezePastDays(from: 140, to: 180, store: store)
        XCTAssertEqual(row(daysAgo: 0)?.targetGrams, 160)
    }

    /// Two changes in a row: the first freeze owns everything before it, the
    /// second owns only the stretch after it.
    func testASecondFreezeDoesNotRewriteTheFirst() {
        TargetHistoryService.freezePastDays(from: 140, to: 150, store: store)
        TargetHistoryService.freezePastDays(from: 150, to: 180, store: store)

        XCTAssertEqual(resolvedTarget(daysAgo: 30, liveTarget: 180), 140)
        XCTAssertEqual(TargetHistoryService.target(on: .now, store: store), 180)
    }

    /// Two changes on the same day are one change: only the last value was ever
    /// the day's target.
    func testTwoChangesInOneDayCollapse() {
        TargetHistoryService.freezePastDays(from: 140, to: 150, store: store)
        TargetHistoryService.freezePastDays(from: 150, to: 180, store: store)
        XCTAssertEqual(TargetHistoryService.changeLog(store: store).count, 2)
    }

    func testApplyingRewritesStoredPastDays() {
        insertRow(daysAgo: 1, target: 140, grams: 145)
        insertRow(daysAgo: 5, target: 100, grams: 120)
        TargetHistoryService.applyToPastDays(180, context: context, store: store)

        XCTAssertEqual(row(daysAgo: 1)?.targetGrams, 180)
        XCTAssertEqual(row(daysAgo: 5)?.targetGrams, 180)
    }

    /// Applying has to erase the log as well as the rows, or a day the log
    /// still covers keeps the old verdict the user just asked to drop.
    func testApplyingErasesAnEarlierFreeze() {
        TargetHistoryService.freezePastDays(from: 140, to: 150, store: store)
        XCTAssertEqual(resolvedTarget(daysAgo: 30, liveTarget: 150), 140)

        TargetHistoryService.applyToPastDays(180, context: context, store: store)
        XCTAssertEqual(resolvedTarget(daysAgo: 30, liveTarget: 180), 180)
        XCTAssertEqual(resolvedTarget(daysAgo: 800, liveTarget: 180), 180)
    }

    /// Today keeps the live target, which `refreshCache` owns.
    func testApplyingDoesNotTouchToday() {
        insertRow(daysAgo: 0, target: 160, grams: 40)
        TargetHistoryService.applyToPastDays(180, context: context, store: store)
        XCTAssertEqual(row(daysAgo: 0)?.targetGrams, 160)
    }

    /// End to end: a day at 145 g under a 140 g target counts as hit, and the
    /// answer to the question decides whether it still does at 180 g. Run on a
    /// day with no stored row, which is the case the log exists for.
    func testTheAnswerDecidesWhetherAnUnrecordedPastDayStillCounts() {
        TargetHistoryService.freezePastDays(from: 140, to: 180, store: store)
        let kept = ProteinDaySummary(
            date: DateHelpers.daysAgo(200),
            grams: 145,
            targetGrams: resolvedTarget(daysAgo: 200, liveTarget: 180)
        )
        XCTAssertTrue(kept.metTarget)

        TargetHistoryService.applyToPastDays(180, context: context, store: store)
        let rejudged = ProteinDaySummary(
            date: DateHelpers.daysAgo(200),
            grams: 145,
            targetGrams: resolvedTarget(daysAgo: 200, liveTarget: 180)
        )
        XCTAssertFalse(rejudged.metTarget)
    }
}
