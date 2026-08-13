import Foundation

#if DEBUG
/// Deterministic data for App Store capture runs, behind `ScreenshotConfig`.
///
/// Real seeded values, not lorem: the totals below sum to the numbers the
/// screenshots claim, and the external source is Apple Health itself, so a
/// capture does not promise an unverified third-party integration.
enum ScreenshotFixtures {
    static let target: Double = 160

    /// Two of our own entries plus one external logger — enough to show the
    /// source rows, the freshness stamps, and a total that is short of target
    /// so the hero reads "36 g left" rather than a finished day.
    static func samples(from start: Date, to end: Date) -> [ProteinSample] {
        let dayStart = DateHelpers.startOfDay()
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            DateHelpers.gregorian.date(byAdding: DateComponents(hour: hour, minute: minute), to: dayStart) ?? dayStart
        }

        let all: [ProteinSample] = [
            ProteinSample(id: "fixture-1", sourceBundleID: "com.apple.Health", sourceName: "Apple Health",
                          grams: 34, endDate: at(8, 10), isOurs: false),
            ProteinSample(id: "fixture-2", sourceBundleID: proteinOwnSourceBundleID, sourceName: "Protein Tracker",
                          grams: 30, endDate: at(10, 45), isOurs: true),
            ProteinSample(id: "fixture-3", sourceBundleID: "com.apple.Health", sourceName: "Apple Health",
                          grams: 35, endDate: at(13, 5), isOurs: false),
            ProteinSample(id: "fixture-4", sourceBundleID: "com.jackwallner.protein.watch", sourceName: "Protein Tracker",
                          grams: 25, endDate: at(16, 20), isOurs: true),
        ]
        return all.filter { $0.endDate >= start && $0.endDate < end }
    }

    /// Daily totals ending today, with today left deliberately short so the
    /// Today capture and the History capture tell the same story.
    ///
    /// Deliberately aperiodic: a short repeating cycle tiled across thirty bars
    /// reads as obviously synthetic in an App Store screenshot, which is
    /// exactly what the capture checklist is meant to catch.
    static func history(days: Int) -> [ProteinDaySummary] {
        let values: [Double] = [
            138, 162, 155, 171, 147, 166, 129, 158, 174, 152,
            141, 168, 160, 133, 177, 149, 163, 156, 170, 144,
            159, 136, 172, 151, 165, 142, 161, 148, 154, 124,
        ]
        let count = max(days, 1)
        return (0..<count).map { offset in
            let date = DateHelpers.daysAgo(count - 1 - offset)
            // Anchor to the end of the table so today is always the last value.
            let index = values.count - count + offset
            return ProteinDaySummary(
                date: date,
                grams: values[max(index, 0) % values.count],
                targetGrams: offset < count / 2 ? 150 : target
            )
        }
    }
}
#endif
