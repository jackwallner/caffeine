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

    /// The hero line. Grams tracked, not grams left: the number the app is for
    /// is what you have actually eaten, and it only ever goes up. A countdown
    /// makes the same day read as a deficit until the last bite, and it has to
    /// clamp at zero, so landing on the target and blowing past it collapse
    /// into one indistinguishable state.
    ///
    /// The target rides along as context rather than as the subject.
    static func trackedHeadline(total: Double, target: Double) -> String {
        guard target > 0 else { return "\(Int(total.rounded())) g tracked" }
        if ProteinReconciliation.hasMetTarget(total: total, target: target) {
            return "\(Int(total.rounded())) g · target hit"
        }
        return "\(Int(total.rounded())) g of \(Int(target.rounded())) g"
    }

    /// Compact variant of `trackedHeadline` for complications.
    static func compactTracked(total: Double, target: Double) -> String {
        guard target > 0 else { return "\(Int(total.rounded()))g" }
        return "\(Int(total.rounded()))/\(Int(target.rounded()))g"
    }

    /// The caption under a tracked number: what the target is, and whether it
    /// has been reached. Kept separate from the number so every surface can
    /// render the same status line at whatever size it has room for.
    static func targetCaption(total: Double, target: Double) -> String {
        guard target > 0 else { return "Set a target" }
        if ProteinReconciliation.hasMetTarget(total: total, target: target) {
            return "\(Int(target.rounded())) g target hit"
        }
        return "of \(Int(target.rounded())) g target"
    }

    /// `targetCaption` for the wrist, where the whole line has to sit under an
    /// 90pt ring on a 42mm screen. Same three states, fewer glyphs.
    static func compactTargetCaption(total: Double, target: Double) -> String {
        guard target > 0 else { return "Set a target" }
        if ProteinReconciliation.hasMetTarget(total: total, target: target) {
            return "\(Int(target.rounded())) g hit"
        }
        return "of \(Int(target.rounded())) g"
    }

    /// The number inside a circular gauge or a corner complication. Those slots
    /// fit about three glyphs, so it is the tracked grams alone. The arc
    /// already carries the progress against the target, and a total needs no
    /// sign or clamp to stay honest past the target.
    static func gaugeValue(total: Double) -> String {
        "\(Int(total.rounded()))"
    }

    /// `gaugeValue` with the unit, for the corner family where the label sits
    /// alone rather than inside a gauge.
    static func gaugeGrams(total: Double) -> String {
        gaugeValue(total: total) + "g"
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
