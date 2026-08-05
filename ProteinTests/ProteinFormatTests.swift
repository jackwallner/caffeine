import XCTest
@testable import Protein

final class ProteinFormatTests: XCTestCase {
    func testGramsRoundToWholeNumbers() {
        XCTAssertEqual(ProteinFormat.grams(124.4), "124 g")
        XCTAssertEqual(ProteinFormat.grams(124.6), "125 g")
        XCTAssertEqual(ProteinFormat.compactGrams(124.6), "125g")
    }

    func testRemainingHeadlineLeadsWithWhatIsLeft() {
        XCTAssertEqual(ProteinFormat.remainingHeadline(total: 124, target: 160), "36 g left")
    }

    /// An overshoot must never render as a negative remaining value.
    func testOverTargetReadsAsOverNotNegative() {
        XCTAssertEqual(ProteinFormat.remainingHeadline(total: 178, target: 160), "18 g over")
        XCTAssertEqual(ProteinFormat.compactRemaining(total: 178, target: 160), "+18g")
    }

    func testExactlyOnTargetReadsAsZeroLeftNotOver() {
        XCTAssertEqual(ProteinFormat.remainingHeadline(total: 160, target: 160), "0 g left")
    }

    func testNoTargetPromptsForOne() {
        XCTAssertEqual(ProteinFormat.remainingHeadline(total: 40, target: 0), "Set a target")
        XCTAssertEqual(ProteinFormat.compactRemaining(total: 40, target: 0), "Set goal")
    }

    func testProgressPairShowsConsumedAgainstTarget() {
        XCTAssertEqual(ProteinFormat.progressPair(total: 124.2, target: 160), "124 / 160 g")
    }

    func testFreshnessBucketsFromSecondsToDates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(ProteinFormat.freshness(from: now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(ProteinFormat.freshness(from: now.addingTimeInterval(-4 * 60), now: now), "4m ago")
        XCTAssertEqual(ProteinFormat.freshness(from: now.addingTimeInterval(-3 * 3600), now: now), "3h ago")
        XCTAssertEqual(ProteinFormat.freshness(from: now.addingTimeInterval(-26 * 3600), now: now), "yesterday")
        XCTAssertEqual(ProteinFormat.freshness(from: now.addingTimeInterval(-3 * 86_400), now: now), "3d ago")
    }

    func testStalenessThresholdIsTwelveHours() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(ProteinFormat.isStale(now.addingTimeInterval(-11 * 3600), now: now))
        XCTAssertTrue(ProteinFormat.isStale(now.addingTimeInterval(-13 * 3600), now: now))
    }
}

final class ReviewPromptEligibilityTests: XCTestCase {
    /// The funnel opens on the third day the target was hit — never on the
    /// third tap, and never for someone who has not hit it.
    func testThreeTargetDaysWithEnoughUseIsEligible() {
        let eligibility = ReviewPromptEligibility(targetHitDays: 3, appLaunchCount: 5, daysSinceFirstOpen: 4)
        XCTAssertTrue(eligibility.isEligible)
    }

    func testTwoTargetDaysIsNotEnough() {
        let eligibility = ReviewPromptEligibility(targetHitDays: 2, appLaunchCount: 20, daysSinceFirstOpen: 30)
        XCTAssertFalse(eligibility.isEligible)
    }

    /// Three target days crammed into one afternoon of testing is not a signal.
    func testFreshInstallIsNeverEligibleEvenWithTargetHits() {
        let eligibility = ReviewPromptEligibility(targetHitDays: 5, appLaunchCount: 2, daysSinceFirstOpen: 0)
        XCTAssertFalse(eligibility.isEligible)
    }

    func testNoTargetDaysIsNeverEligible() {
        let eligibility = ReviewPromptEligibility(targetHitDays: 0, appLaunchCount: 40, daysSinceFirstOpen: 60)
        XCTAssertFalse(eligibility.isEligible)
    }
}

final class DateHelpersTests: XCTestCase {
    func testDayKeyIsZeroPaddedAndSortable() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 7
        components.hour = 23
        let date = DateHelpers.gregorian.date(from: components)!
        XCTAssertEqual(DateHelpers.dayKey(for: date), "2026-03-07")
    }

    func testEndOfDayIsTheNextMidnight() {
        let start = DateHelpers.startOfDay()
        let end = DateHelpers.endOfDay()
        XCTAssertEqual(end.timeIntervalSince(start), 86_400, accuracy: 3600, "Allow an hour for DST transitions")
        XCTAssertTrue(end > .now)
    }

    func testDaysAgoCountsBackFromMidnight() {
        let sevenDaysAgo = DateHelpers.daysAgo(7)
        XCTAssertEqual(sevenDaysAgo, DateHelpers.startOfDay(sevenDaysAgo))
        XCTAssertEqual(DateHelpers.daysAgo(0), DateHelpers.startOfDay())
    }
}
