import Foundation

#if DEBUG
enum ScreenshotFixtures {
    static func samples(from start: Date, to end: Date) -> [CaffeineSample] {
        let now = Date.now
        let all = [
            CaffeineSample(
                id: "fixture-morning",
                sourceBundleID: "com.apple.Health",
                sourceName: "Apple Health",
                milligrams: 80,
                endDate: now.addingTimeInterval(-8 * 3600),
                isOurs: false
            ),
            CaffeineSample(
                id: "fixture-coffee",
                sourceBundleID: caffeineOwnSourceBundleID,
                sourceName: "Caffeine",
                milligrams: 120,
                endDate: now.addingTimeInterval(-4 * 3600),
                isOurs: true
            ),
            CaffeineSample(
                id: "fixture-tea",
                sourceBundleID: "com.apple.Health",
                sourceName: "Apple Health",
                milligrams: 60,
                endDate: now.addingTimeInterval(-90 * 60),
                isOurs: false
            ),
        ]
        return all.filter { $0.endDate >= start && $0.endDate < end }
    }

    static func history(days: Int) -> [CaffeineDaySummary] {
        let consumed = [160.0, 240, 180, 310, 120, 205, 260, 145, 280, 195, 225, 170, 300, 210]
        let bedtime = [18.0, 42, 27, 65, 12, 33, 48, 16, 54, 24, 39, 20, 61, 35]
        let count = max(days, 1)
        return (0..<count).map { offset in
            let index = (consumed.count - count + offset).modulo(consumed.count)
            return CaffeineDaySummary(
                date: DateHelpers.daysAgo(count - 1 - offset),
                milligrams: consumed[index],
                estimatedAtBedtime: bedtime[index]
            )
        }
    }
}

private extension Int {
    func modulo(_ divisor: Int) -> Int {
        let result = self % divisor
        return result >= 0 ? result : result + divisor
    }
}
#endif
