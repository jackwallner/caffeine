import Foundation

/// What a month of days adds up to. Pure, so the streak rules are unit tested
/// rather than eyeballed against whatever the simulator happened to have logged.
struct ProteinInsights: Sendable, Equatable {
    /// Days on target ending at the most recent day that can still be judged.
    let currentStreak: Int
    let bestStreak: Int
    let daysOnTarget: Int
    /// Days in the window, including ones with nothing logged.
    let daysCounted: Int
    let average: Double
    /// Average over the window immediately before this one, when there is one.
    let previousAverage: Double?
    let bestDay: ProteinDaySummary?

    /// Fraction of the average change against the previous window, for a badge.
    /// Nil when there is no previous window, or it averaged zero.
    var averageChange: Double? {
        guard let previousAverage, previousAverage > 0 else { return nil }
        return (average - previousAverage) / previousAverage
    }

    static let empty = ProteinInsights(
        currentStreak: 0,
        bestStreak: 0,
        daysOnTarget: 0,
        daysCounted: 0,
        average: 0,
        previousAverage: nil,
        bestDay: nil
    )
}

/// A week of days collapsed into one bar, for ranges too long to draw a bar per
/// day. Averages rather than sums: the chart draws the daily target as a line
/// across the same axis, and a weekly *sum* against a daily target is a
/// comparison between two different units.
struct ProteinWeekSummary: Identifiable, Sendable, Equatable {
    let weekStart: Date
    let averageGrams: Double
    let averageTarget: Double
    let daysOnTarget: Int
    let dayCount: Int

    var id: Date { weekStart }
    /// A part-week at either end of the range is judged the same way a day is:
    /// on the days it actually has.
    var metTarget: Bool { dayCount > 0 && daysOnTarget * 2 > dayCount }
}

enum ProteinInsightsBuilder {
    /// Groups `days` into calendar weeks, oldest first. Partial weeks at the
    /// start and end of the range are kept — dropping them would silently move
    /// the range the user asked for.
    static func weeks(from days: [ProteinDaySummary]) -> [ProteinWeekSummary] {
        var buckets: [Date: [ProteinDaySummary]] = [:]
        for day in days {
            guard let start = DateHelpers.gregorian.dateInterval(of: .weekOfYear, for: day.date)?.start else { continue }
            buckets[start, default: []].append(day)
        }
        return buckets.keys.sorted().map { start in
            let group = buckets[start] ?? []
            return ProteinWeekSummary(
                weekStart: start,
                averageGrams: average(days: group),
                averageTarget: group.isEmpty
                    ? 0
                    : group.reduce(0) { $0 + $1.targetGrams } / Double(group.count),
                daysOnTarget: group.filter(\.metTarget).count,
                dayCount: group.count
            )
        }
    }

    /// Builds the figures for the Protein+ tab.
    ///
    /// `days` and `previous` are both oldest-first, the order `fetchHistory`
    /// returns. `previous` is only used for the average comparison; a streak
    /// deliberately does not reach back into it, because the window is what the
    /// subscriber can actually see.
    static func make(days: [ProteinDaySummary], previous: [ProteinDaySummary] = []) -> ProteinInsights {
        guard !days.isEmpty else { return .empty }
        let sorted = days.sorted { $0.date < $1.date }
        return ProteinInsights(
            currentStreak: currentStreak(days: sorted),
            bestStreak: bestStreak(days: sorted),
            daysOnTarget: sorted.filter(\.metTarget).count,
            daysCounted: sorted.count,
            average: average(days: sorted),
            previousAverage: previous.isEmpty ? nil : average(days: previous),
            bestDay: sorted.max { lhs, rhs in
                if lhs.grams != rhs.grams { return lhs.grams < rhs.grams }
                // Ties go to the earlier day, so a best day stops moving around
                // once it is set.
                return lhs.date > rhs.date
            }.flatMap { $0.grams > 0 ? $0 : nil }
        )
    }

    static func average(days: [ProteinDaySummary]) -> Double {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.grams } / Double(days.count)
    }

    /// Consecutive days on target, counting back from the end of the window.
    ///
    /// A today that has not been hit *yet* does not break the streak: at 9am
    /// nobody has eaten their day's protein, and a counter that resets every
    /// morning and refills every evening is noise rather than a streak. Today
    /// only counts once it is met.
    static func currentStreak(days: [ProteinDaySummary], now: Date = .now) -> Int {
        var remaining = days.sorted { $0.date < $1.date }
        if let last = remaining.last, DateHelpers.isSameDay(last.date, now), !last.metTarget {
            remaining.removeLast()
        }
        var streak = 0
        for day in remaining.reversed() {
            guard day.metTarget else { break }
            streak += 1
        }
        return streak
    }

    static func bestStreak(days: [ProteinDaySummary]) -> Int {
        var best = 0
        var running = 0
        for day in days.sorted(by: { $0.date < $1.date }) {
            if day.metTarget {
                running += 1
                best = max(best, running)
            } else {
                running = 0
            }
        }
        return best
    }
}
