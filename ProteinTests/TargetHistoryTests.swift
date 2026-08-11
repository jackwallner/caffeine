import SwiftData
import XCTest
@testable import Protein

/// What a target change does to the days behind it.
///
/// The trap this covers: a past day with no cached row falls back to the
/// *current* target when history is drawn, so leaving the past alone is not the
/// same as doing nothing. Keeping the past has to write.
@MainActor
final class TargetHistoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([DailyProteinRecord.self, LocalProteinEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    override func tearDown() {
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

    /// Keeping the past means materializing the old target onto days that had
    /// no row, or they silently inherit whatever the target becomes next.
    func testFreezingWritesTheOldTargetOntoDaysThatHadNoRow() {
        insertRow(daysAgo: 3, target: 140, grams: 150)
        TargetHistoryService.freezePastDays(at: 140, context: context)

        XCTAssertEqual(row(daysAgo: 1)?.targetGrams, 140)
        XCTAssertEqual(row(daysAgo: 10)?.targetGrams, 140)
        XCTAssertEqual(row(daysAgo: TargetHistoryService.windowDays - 1)?.targetGrams, 140)
    }

    /// A day that already carries a target may carry an older one still, and
    /// freezing is not the moment to flatten that.
    func testFreezingLeavesDaysThatAlreadyCarryATargetAlone() {
        insertRow(daysAgo: 2, target: 100, grams: 120)
        TargetHistoryService.freezePastDays(at: 140, context: context)
        XCTAssertEqual(row(daysAgo: 2)?.targetGrams, 100)
    }

    func testFreezingDoesNotTouchToday() {
        insertRow(daysAgo: 0, target: 160, grams: 40)
        TargetHistoryService.freezePastDays(at: 140, context: context)
        XCTAssertEqual(row(daysAgo: 0)?.targetGrams, 160)
    }

    /// Freezing twice must not duplicate a day: the row's date key is unique,
    /// and a second pass that re-inserted would trip it.
    func testFreezingIsIdempotent() {
        TargetHistoryService.freezePastDays(at: 140, context: context)
        let first = rows().count
        TargetHistoryService.freezePastDays(at: 150, context: context)
        XCTAssertEqual(rows().count, first)
        // The second pass must not rewrite what the first one established.
        XCTAssertEqual(row(daysAgo: 1)?.targetGrams, 140)
    }

    func testApplyingRewritesStoredPastDays() {
        insertRow(daysAgo: 1, target: 140, grams: 145)
        insertRow(daysAgo: 5, target: 100, grams: 120)
        TargetHistoryService.applyToPastDays(180, context: context)

        XCTAssertEqual(row(daysAgo: 1)?.targetGrams, 180)
        XCTAssertEqual(row(daysAgo: 5)?.targetGrams, 180)
    }

    /// Today keeps the live target, which `refreshCache` owns.
    func testApplyingDoesNotTouchToday() {
        insertRow(daysAgo: 0, target: 160, grams: 40)
        TargetHistoryService.applyToPastDays(180, context: context)
        XCTAssertEqual(row(daysAgo: 0)?.targetGrams, 160)
    }

    /// End to end: a day at 145 g under a 140 g target counts as hit, and the
    /// answer to the question decides whether it still does at 180 g.
    func testTheAnswerDecidesWhetherAPastDayStillCounts() {
        insertRow(daysAgo: 1, target: 140, grams: 145)

        TargetHistoryService.freezePastDays(at: 140, context: context)
        let kept = ProteinDaySummary(
            date: DateHelpers.daysAgo(1),
            grams: 145,
            targetGrams: row(daysAgo: 1)?.targetGrams ?? 0
        )
        XCTAssertTrue(kept.metTarget)

        TargetHistoryService.applyToPastDays(180, context: context)
        let rejudged = ProteinDaySummary(
            date: DateHelpers.daysAgo(1),
            grams: 145,
            targetGrams: row(daysAgo: 1)?.targetGrams ?? 0
        )
        XCTAssertFalse(rejudged.metTarget)
    }
}
