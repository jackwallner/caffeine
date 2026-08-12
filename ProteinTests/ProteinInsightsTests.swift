import XCTest
@testable import Protein

/// The Protein+ tab's figures. Streaks are the part users check against their
/// own memory, so the rules are pinned here rather than trusted to a simulator
/// that happens to have the right days in it.
final class ProteinInsightsTests: XCTestCase {
    private func day(_ daysAgo: Int, grams: Double, target: Double = 100) -> ProteinDaySummary {
        ProteinDaySummary(date: DateHelpers.daysAgo(daysAgo), grams: grams, targetGrams: target)
    }

    func testEmptyWindowReportsNothing() {
        let insights = ProteinInsightsBuilder.make(days: [])
        XCTAssertEqual(insights, .empty)
        XCTAssertNil(insights.bestDay)
    }

    /// A day still in progress is not a broken streak. At 9am nobody has eaten
    /// their protein yet, and a counter that resets every morning is noise.
    func testTodayFallingShortDoesNotBreakTheStreak() {
        let days = [
            day(3, grams: 120),
            day(2, grams: 130),
            day(1, grams: 110),
            day(0, grams: 20),
        ]
        XCTAssertEqual(ProteinInsightsBuilder.currentStreak(days: days), 3)
    }

    func testTodayOnTargetCountsTowardTheStreak() {
        let days = [
            day(2, grams: 130),
            day(1, grams: 110),
            day(0, grams: 105),
        ]
        XCTAssertEqual(ProteinInsightsBuilder.currentStreak(days: days), 3)
    }

    /// A missed day that is not today ends the run, however good the days
    /// before it were.
    func testAMissedDayEndsTheCurrentStreak() {
        let days = [
            day(4, grams: 150),
            day(3, grams: 150),
            day(2, grams: 40),
            day(1, grams: 120),
            day(0, grams: 120),
        ]
        let insights = ProteinInsightsBuilder.make(days: days)
        XCTAssertEqual(insights.currentStreak, 2)
        XCTAssertEqual(insights.bestStreak, 2)
        XCTAssertEqual(insights.daysOnTarget, 4)
        XCTAssertEqual(insights.daysCounted, 5)
    }

    func testBestStreakSurvivesALaterCollapse() {
        let days = [
            day(6, grams: 120),
            day(5, grams: 120),
            day(4, grams: 120),
            day(3, grams: 10),
            day(2, grams: 120),
            day(1, grams: 10),
            day(0, grams: 10),
        ]
        let insights = ProteinInsightsBuilder.make(days: days)
        XCTAssertEqual(insights.bestStreak, 3)
        XCTAssertEqual(insights.currentStreak, 0)
    }

    /// Each day is judged against the target it carried, which is the whole
    /// point of snapshotting the target on the day row.
    func testDaysAreJudgedAgainstTheirOwnTarget() {
        let days = [
            day(1, grams: 90, target: 80),
            day(0, grams: 90, target: 140),
        ]
        let insights = ProteinInsightsBuilder.make(days: days)
        XCTAssertEqual(insights.daysOnTarget, 1)
        XCTAssertEqual(insights.currentStreak, 1)
    }

    func testAverageIncludesDaysWithNothingLogged() {
        let days = [day(1, grams: 100), day(0, grams: 0)]
        XCTAssertEqual(ProteinInsightsBuilder.make(days: days).average, 50)
    }

    func testAverageChangeComparesWithThePreviousWindow() {
        let current = [day(1, grams: 120), day(0, grams: 120)]
        let previous = [day(3, grams: 100), day(2, grams: 100)]
        let insights = ProteinInsightsBuilder.make(days: current, previous: previous)
        XCTAssertEqual(insights.previousAverage, 100)
        XCTAssertEqual(insights.averageChange ?? 0, 0.2, accuracy: 0.0001)
    }

    func testAverageChangeIsAbsentWithoutAPreviousWindow() {
        XCTAssertNil(ProteinInsightsBuilder.make(days: [day(0, grams: 120)]).averageChange)
    }

    /// A window of nothing but zeros has no best day to name.
    func testBestDayNeedsSomethingLogged() {
        XCTAssertNil(ProteinInsightsBuilder.make(days: [day(1, grams: 0), day(0, grams: 0)]).bestDay)
        XCTAssertEqual(
            ProteinInsightsBuilder.make(days: [day(1, grams: 90), day(0, grams: 140)]).bestDay?.grams,
            140
        )
    }

    /// Ties go to the earlier day so a best day stops moving once it is set.
    func testTiedBestDaysKeepTheEarlierOne() {
        let days = [day(2, grams: 150), day(1, grams: 150), day(0, grams: 20)]
        let best = ProteinInsightsBuilder.make(days: days).bestDay
        XCTAssertEqual(best?.date, DateHelpers.daysAgo(2))
    }

    func testUnsortedInputIsHandled() {
        let days = [day(0, grams: 120), day(2, grams: 120), day(1, grams: 120)]
        XCTAssertEqual(ProteinInsightsBuilder.make(days: days).currentStreak, 3)
    }

    // MARK: - Weekly rollup

    /// Past a quarter the chart draws a bar per week. Every day has to land in
    /// exactly one bucket, or the rollup quietly drops history.
    func testEveryDayLandsInExactlyOneWeek() {
        let days = (0..<70).map { day($0, grams: 100) }
        let weeks = ProteinInsightsBuilder.weeks(from: days)
        XCTAssertEqual(weeks.reduce(0) { $0 + $1.dayCount }, 70)
        XCTAssertEqual(weeks.count, Set(weeks.map(\.weekStart)).count)
    }

    func testWeeksComeBackOldestFirst() {
        let weeks = ProteinInsightsBuilder.weeks(from: (0..<40).map { day($0, grams: 100) })
        XCTAssertEqual(weeks.map(\.weekStart), weeks.map(\.weekStart).sorted())
    }

    /// Averages, not sums: the chart draws the daily target as a line across
    /// the same axis, and a weekly sum against a daily target compares two
    /// different units.
    func testAWeekReportsTheDailyAverageNotTheWeeklySum() throws {
        let days = (0..<7).map { day($0, grams: 140, target: 120) }
        let week = try XCTUnwrap(ProteinInsightsBuilder.weeks(from: days).first)
        XCTAssertEqual(week.averageGrams, 140, accuracy: 0.001)
        XCTAssertEqual(week.averageTarget, 120, accuracy: 0.001)
    }

    /// A part-week at the edge of the range is judged on the days it has, so
    /// "All" starting mid-week does not open on a failed bar.
    func testAPartWeekIsJudgedOnTheDaysItHas() {
        let onTarget = ProteinWeekSummary(
            weekStart: DateHelpers.daysAgo(3),
            averageGrams: 150,
            averageTarget: 120,
            daysOnTarget: 2,
            dayCount: 3
        )
        XCTAssertTrue(onTarget.metTarget)

        let short = ProteinWeekSummary(
            weekStart: DateHelpers.daysAgo(3),
            averageGrams: 90,
            averageTarget: 120,
            daysOnTarget: 1,
            dayCount: 3
        )
        XCTAssertFalse(short.metTarget)
    }

    func testEmptyHistoryRollsUpToNoWeeks() {
        XCTAssertTrue(ProteinInsightsBuilder.weeks(from: []).isEmpty)
    }
}
