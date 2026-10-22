import XCTest
@testable import Caffeine

final class UnfoldedSplitTests: XCTestCase {

    func testCompactWidthKeepsSingleColumn() {
        XCTAssertNil(UnfoldedSplit.make(width: 951, isRegularWidth: false, fold: 474...477))
    }

    func testOuterDisplayKeepsSingleColumn() {
        XCTAssertNil(UnfoldedSplit.make(width: 466, isRegularWidth: true, fold: nil))
    }

    func testUnfoldedPortraitIsTooNarrowForTwoPanes() {
        XCTAssertNil(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil))
    }

    func testPanesMeetTheFoldEdges() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 470...481)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 470, secondaryX: 481, secondaryWidth: 470))
    }

    func testMissingFoldSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    func testOffCentreFoldThatStarvesAPaneSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 600...610)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    func testExactMinimumWidthSplits() {
        let split = UnfoldedSplit.make(width: 720, isRegularWidth: true, fold: nil)
        XCTAssertEqual(split?.primaryWidth, 360)
        XCTAssertEqual(split?.secondaryWidth, 360)
    }
}
