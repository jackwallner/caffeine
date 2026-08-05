import Foundation

/// Every place a gram figure or a freshness stamp is rendered. Centralized
/// because the complication, the widget, the ring, and the Sources rows all
/// have to agree — a number that reads `124g` on the wrist and `124.4 g` in the
/// app is the kind of drift this app exists to not have.
enum ProteinFormat {
    /// Whole grams. Protein targets are set in round numbers and food labels
    /// report round numbers, so a decimal here is noise, not precision.
    static func grams(_ value: Double) -> String {
        "\(Int(value.rounded())) g"
    }

    /// No space, for the tight complication families.
    static func compactGrams(_ value: Double) -> String {
        "\(Int(value.rounded()))g"
    }

    /// The hero line. Remaining grams answer "what should I do next?", which is
    /// the question the app is for; consumed grams answer "what have I done?".
    static func remainingHeadline(total: Double, target: Double) -> String {
        guard target > 0 else { return "Set a target" }
        let overage = ProteinReconciliation.overage(total: total, target: target)
        if overage > 0.5 {
            return "\(Int(overage.rounded())) g over"
        }
        return "\(Int(ProteinReconciliation.remaining(total: total, target: target).rounded())) g left"
    }

    /// Compact variant of `remainingHeadline` for complications.
    static func compactRemaining(total: Double, target: Double) -> String {
        guard target > 0 else { return "Set goal" }
        let overage = ProteinReconciliation.overage(total: total, target: target)
        if overage > 0.5 {
            return "+\(Int(overage.rounded()))g"
        }
        return "\(Int(ProteinReconciliation.remaining(total: total, target: target).rounded()))g left"
    }

    /// "124 / 160 g" — consumed against target, for the rectangular families.
    static func progressPair(total: Double, target: Double) -> String {
        "\(Int(total.rounded())) / \(Int(target.rounded())) g"
    }

    /// How long ago a source last wrote. Short by design: this sits at the end
    /// of a row that already names the app.
    static func freshness(from date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days)d ago" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// A source that has not written in a long time is reported with its value
    /// *and* its age rather than silently as current — the freshness complaints
    /// in `docs/positioning.md` §4 are all stale numbers presented as fresh.
    static func isStale(_ date: Date, now: Date = .now, hours: Int = 12) -> Bool {
        now.timeIntervalSince(date) > TimeInterval(hours) * 3600
    }
}
