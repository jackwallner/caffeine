import XCTest
@testable import Protein

/// The multi-source cases are the only part of this app that can be verified
/// without a real device and two food loggers installed, so this is where the
/// tests earn their keep.
final class ProteinReconciliationTests: XCTestCase {
    private let ours = proteinOwnSourceBundleID
    private let watch = "com.jackwallner.protein.watch"
    private let macroFactor = "com.macrofactorapp.macrofactor"
    private let cronometer = "com.cronometer.ios"

    private func sample(
        _ id: String,
        _ bundleID: String,
        _ grams: Double,
        minutesAgo: Int = 0,
        name: String? = nil
    ) -> ProteinSample {
        ProteinSample(
            id: id,
            sourceBundleID: bundleID,
            sourceName: name ?? bundleID,
            grams: grams,
            endDate: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60),
            isOurs: proteinOwnSourceBundleIDs.contains(bundleID)
        )
    }

    // MARK: - Totals

    func testTotalSumsEveryIncludedSource() {
        let samples = [
            sample("a", ours, 30),
            sample("b", macroFactor, 40),
            sample("c", cronometer, 20),
        ]
        XCTAssertEqual(ProteinReconciliation.total(samples: samples, selection: .init()), 90)
    }

    func testExcludedSourceIsDroppedFromTheTotal() {
        let samples = [
            sample("a", ours, 30),
            sample("b", macroFactor, 40),
            sample("c", cronometer, 20),
        ]
        let selection = ProteinSourceSelection(excludedBundleIDs: [cronometer])
        XCTAssertEqual(ProteinReconciliation.total(samples: samples, selection: selection), 70)
    }

    /// Excluding our own bundle ID must not silently drop grams the user typed
    /// into this app — that reads as data loss no matter what the setting says.
    func testOurOwnSourceCannotBeExcluded() {
        let samples = [sample("a", ours, 30), sample("b", macroFactor, 40)]
        let selection = ProteinSourceSelection(excludedBundleIDs: [ours, macroFactor])
        XCTAssertEqual(ProteinReconciliation.total(samples: samples, selection: selection), 30)
    }

    /// Phone and wrist write under different bundle IDs; both are us.
    func testWatchEntriesCountAsOurs() {
        let samples = [sample("a", ours, 30), sample("b", watch, 25)]
        let selection = ProteinSourceSelection(excludedBundleIDs: [ours, watch])
        XCTAssertEqual(ProteinReconciliation.total(samples: samples, selection: selection), 55)
    }

    /// Several samples from one source are separate meals, not duplicates.
    func testRepeatedSamplesFromOneSourceAllCount() {
        let samples = [
            sample("a", macroFactor, 30),
            sample("b", macroFactor, 25),
            sample("c", macroFactor, 12),
        ]
        XCTAssertEqual(ProteinReconciliation.total(samples: samples, selection: .init()), 67)
    }

    func testNegativeGramsAreIgnoredRatherThanSubtracted() {
        let samples = [sample("a", ours, 30), sample("b", macroFactor, -10)]
        XCTAssertEqual(ProteinReconciliation.total(samples: samples, selection: .init()), 30)
    }

    func testEmptyDayTotalsZero() {
        XCTAssertEqual(ProteinReconciliation.total(samples: [], selection: .init()), 0)
    }

    // MARK: - Sources

    func testSourcesGroupByAppAndKeepTheNewestTimestamp() throws {
        let samples = [
            sample("a", macroFactor, 30, minutesAgo: 300, name: "MacroFactor"),
            sample("b", macroFactor, 25, minutesAgo: 4, name: "MacroFactor"),
            sample("c", ours, 20, minutesAgo: 60, name: "Protein Tracker"),
        ]
        let sources = ProteinReconciliation.sources(samples: samples, selection: .init())

        XCTAssertEqual(sources.count, 2)
        // Ours sorts first regardless of contribution.
        XCTAssertEqual(sources.first?.bundleID, ours)
        let external = try XCTUnwrap(sources.first { $0.bundleID == macroFactor })
        XCTAssertEqual(external.grams, 55)
        XCTAssertEqual(external.sampleCount, 2)
        XCTAssertEqual(
            external.latestEntry.timeIntervalSinceNow,
            -240,
            accuracy: 5,
            "Freshness must report the newest sample, not the first one seen"
        )
    }

    func testExcludedSourceStillAppearsButIsMarkedExcluded() {
        let samples = [sample("a", cronometer, 20, name: "Cronometer")]
        let selection = ProteinSourceSelection(excludedBundleIDs: [cronometer])
        let sources = ProteinReconciliation.sources(samples: samples, selection: selection)

        XCTAssertEqual(sources.count, 1, "A switched-off source must stay visible so it can be switched back on")
        XCTAssertFalse(sources[0].isIncluded)
        XCTAssertEqual(sources[0].grams, 20, "The row still reports what that source would contribute")
    }

    /// The phone and the watch write under different bundle IDs, but they are
    /// one app to the person reading the Sources screen. Two rows both named
    /// "Protein Tracker" would look like the double-count the screen exists to
    /// help them find.
    func testPhoneAndWatchEntriesCollapseIntoOneRow() throws {
        let samples = [
            sample("a", ours, 30, minutesAgo: 120, name: "Protein Tracker"),
            sample("b", watch, 25, minutesAgo: 10, name: "Protein Tracker"),
        ]
        let sources = ProteinReconciliation.sources(samples: samples, selection: .init())

        XCTAssertEqual(sources.count, 1)
        let row = try XCTUnwrap(sources.first)
        XCTAssertEqual(row.bundleID, ours)
        XCTAssertEqual(row.grams, 55)
        XCTAssertEqual(row.sampleCount, 2)
        XCTAssertTrue(row.isOurs)
        XCTAssertEqual(row.latestEntry.timeIntervalSinceNow, -600, accuracy: 5)
    }

    func testSourcesSortExternalAppsByContribution() {
        let samples = [
            sample("a", cronometer, 15, name: "Cronometer"),
            sample("b", macroFactor, 60, name: "MacroFactor"),
        ]
        let sources = ProteinReconciliation.sources(samples: samples, selection: .init())
        XCTAssertEqual(sources.map(\.bundleID), [macroFactor, cronometer])
    }

    // MARK: - Duplicate risk

    func testTwoExternalLoggersRaiseDuplicateRisk() {
        let samples = [
            sample("a", macroFactor, 40),
            sample("b", cronometer, 35),
            sample("c", ours, 20),
        ]
        let sources = ProteinReconciliation.sources(samples: samples, selection: .init())
        XCTAssertTrue(ProteinReconciliation.hasDuplicateRisk(sources: sources))
    }

    func testOneExternalLoggerPlusOurOwnEntriesIsNotDuplicateRisk() {
        let samples = [sample("a", macroFactor, 40), sample("b", ours, 20), sample("c", watch, 25)]
        let sources = ProteinReconciliation.sources(samples: samples, selection: .init())
        XCTAssertFalse(
            ProteinReconciliation.hasDuplicateRisk(sources: sources),
            "Our own entries are not a second food logger"
        )
    }

    func testTurningOneLoggerOffClearsDuplicateRisk() {
        let samples = [sample("a", macroFactor, 40), sample("b", cronometer, 35)]
        let selection = ProteinSourceSelection(excludedBundleIDs: [cronometer])
        let sources = ProteinReconciliation.sources(samples: samples, selection: selection)
        XCTAssertFalse(ProteinReconciliation.hasDuplicateRisk(sources: sources))
    }

    /// A source that is enabled but contributed nothing today is not evidence
    /// of double counting.
    func testSilentSecondLoggerIsNotDuplicateRisk() {
        let samples = [sample("a", macroFactor, 40), sample("b", cronometer, 0)]
        let sources = ProteinReconciliation.sources(samples: samples, selection: .init())
        XCTAssertFalse(ProteinReconciliation.hasDuplicateRisk(sources: sources))
    }

    // MARK: - Remaining / overage / progress

    func testRemainingNeverGoesNegative() {
        XCTAssertEqual(ProteinReconciliation.remaining(total: 180, target: 160), 0)
        XCTAssertEqual(ProteinReconciliation.remaining(total: 100, target: 160), 60)
    }

    func testOverageReportsTheOvershoot() {
        XCTAssertEqual(ProteinReconciliation.overage(total: 178, target: 160), 18)
        XCTAssertEqual(ProteinReconciliation.overage(total: 100, target: 160), 0)
    }

    func testProgressIsZeroWithoutATarget() {
        XCTAssertEqual(ProteinReconciliation.progress(total: 80, target: 0), 0)
    }

    func testProgressOvershootsRatherThanClamping() {
        XCTAssertEqual(ProteinReconciliation.progress(total: 320, target: 160), 2, accuracy: 0.0001)
    }

    /// Float drift must not be the difference between a met target and a missed
    /// one — a day logged as 159.7 g against a 160 g target counts.
    func testTargetIsMetWithinHalfAGram() {
        XCTAssertTrue(ProteinReconciliation.hasMetTarget(total: 159.7, target: 160))
        XCTAssertTrue(ProteinReconciliation.hasMetTarget(total: 160, target: 160))
        XCTAssertFalse(ProteinReconciliation.hasMetTarget(total: 158, target: 160))
        XCTAssertFalse(ProteinReconciliation.hasMetTarget(total: 100, target: 0))
    }

    // MARK: - Selection

    func testSelectionRoundTripsIncludeAndExclude() {
        var selection = ProteinSourceSelection()
        XCTAssertTrue(selection.includes(bundleID: macroFactor, isOurs: false))

        selection.setIncluded(false, bundleID: macroFactor)
        XCTAssertFalse(selection.includes(bundleID: macroFactor, isOurs: false))

        selection.setIncluded(true, bundleID: macroFactor)
        XCTAssertTrue(selection.includes(bundleID: macroFactor, isOurs: false))
    }

    /// Opt-out, not opt-in: a food logger that starts writing protein tomorrow
    /// has to count tomorrow, or a fresh install shows zero and the "import
    /// from your existing logger" promise fails on day one.
    func testUnknownSourcesCountByDefault() {
        let selection = ProteinSourceSelection(excludedBundleIDs: [cronometer])
        XCTAssertTrue(selection.includes(bundleID: "com.brand.new.logger", isOurs: false))
    }
}
