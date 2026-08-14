import XCTest
@testable import Protein

final class ProteinFormatTests: XCTestCase {
    func testGramsRoundToWholeNumbers() {
        XCTAssertEqual(ProteinFormat.grams(124.4), "124 g")
        XCTAssertEqual(ProteinFormat.grams(124.6), "125 g")
        XCTAssertEqual(ProteinFormat.compactGrams(124.6), "125g")
    }

    /// The hero counts what has been tracked, not what is missing.
    func testTrackedHeadlineLeadsWithWhatIsTracked() {
        XCTAssertEqual(ProteinFormat.trackedHeadline(total: 124, target: 160), "124 g of 160 g")
        XCTAssertEqual(ProteinFormat.compactTracked(total: 124, target: 160), "124/160g")
    }

    /// Past the target the total keeps climbing. Nothing clamps, nothing goes
    /// negative, and nothing is signed. 178 g eaten reads as 178 g.
    func testOverTargetKeepsCountingUp() {
        XCTAssertEqual(ProteinFormat.trackedHeadline(total: 178, target: 160), "178 g · target hit")
        XCTAssertEqual(ProteinFormat.compactTracked(total: 178, target: 160), "178/160g")
        XCTAssertEqual(ProteinFormat.targetCaption(total: 178, target: 160), "160 g target hit")
    }

    func testExactlyOnTargetReadsAsHit() {
        XCTAssertEqual(ProteinFormat.trackedHeadline(total: 160, target: 160), "160 g · target hit")
        XCTAssertEqual(ProteinFormat.targetCaption(total: 160, target: 160), "160 g target hit")
    }

    func testUnderTargetNamesTheTargetWithoutCountingDown() {
        XCTAssertEqual(ProteinFormat.targetCaption(total: 124, target: 160), "of 160 g target")
    }

    /// With no target the tracked grams still stand on their own; only the
    /// caption asks for one.
    func testNoTargetStillShowsTheTotal() {
        XCTAssertEqual(ProteinFormat.trackedHeadline(total: 40, target: 0), "40 g tracked")
        XCTAssertEqual(ProteinFormat.compactTracked(total: 40, target: 0), "40g")
        XCTAssertEqual(ProteinFormat.targetCaption(total: 40, target: 0), "Set a target")
    }

    /// The circular widget and the circular/corner complications have room for
    /// a number and nothing else. That number is the total, which needs no
    /// sign and no clamp to stay honest either side of the target.
    func testGaugeValueIsTheTrackedTotal() {
        XCTAssertEqual(ProteinFormat.gaugeValue(total: 124), "124")
        XCTAssertEqual(ProteinFormat.gaugeValue(total: 185), "185")
        XCTAssertEqual(ProteinFormat.gaugeValue(total: 0), "0")
    }

    func testGaugeGramsCarriesTheUnit() {
        XCTAssertEqual(ProteinFormat.gaugeGrams(total: 124), "124g")
        XCTAssertEqual(ProteinFormat.gaugeGrams(total: 185.4), "185g")
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
