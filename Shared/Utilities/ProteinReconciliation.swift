import Foundation

/// One dietary-protein sample flattened to the fields reconciliation needs.
///
/// HealthKit is the single source of truth for our own entries too (see
/// `docs/plan.md` §4), so a sample we wrote and a sample MacroFactor wrote are
/// the same shape here. `isOurs` exists for presentation and for the rule that
/// our own source can never be switched off, not for arithmetic.
struct ProteinSample: Sendable, Equatable, Identifiable {
    /// HealthKit sample UUID string, or the local entry's UUID when write
    /// authorization was denied and the entry lives only on this device.
    let id: String
    let sourceBundleID: String
    let sourceName: String
    let grams: Double
    /// When the food was eaten, per the writing app. Drives the freshness row.
    let endDate: Date
    let isOurs: Bool
    /// True for grams HealthKit refused to take, which live only in the local
    /// fallback table. They count exactly like everything else; the flag is so
    /// the Sources screen can say where they are, not so the sum can skip them.
    let isLocalOnly: Bool

    init(
        id: String,
        sourceBundleID: String,
        sourceName: String,
        grams: Double,
        endDate: Date,
        isOurs: Bool,
        isLocalOnly: Bool = false
    ) {
        self.id = id
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.grams = grams
        self.endDate = endDate
        self.isOurs = isOurs
        self.isLocalOnly = isLocalOnly
    }
}

/// One history row with the target that was in force on that day.
struct ProteinDaySummary: Sendable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let grams: Double
    let targetGrams: Double

    var metTarget: Bool {
        ProteinReconciliation.hasMetTarget(total: grams, target: targetGrams)
    }
}

/// Which external sources count toward the daily total.
///
/// Opt-out rather than opt-in: a source the user has never seen still counts,
/// because a brand-new install whose food logger already writes protein should
/// show the right number on day one rather than a zero and a hunt through
/// settings. The Sources screen exists to turn a double-counting app *off*.
struct ProteinSourceSelection: Sendable, Equatable {
    /// Bundle IDs the user explicitly switched off.
    var excludedBundleIDs: Set<String>

    init(excludedBundleIDs: Set<String> = []) {
        self.excludedBundleIDs = excludedBundleIDs
    }

    /// Our own entries always count. Excluding them would silently drop grams
    /// the user typed in this app, which reads as a bug no matter the setting.
    func includes(bundleID: String, isOurs: Bool) -> Bool {
        isOurs || !excludedBundleIDs.contains(bundleID)
    }

    mutating func setIncluded(_ included: Bool, bundleID: String) {
        if included {
            excludedBundleIDs.remove(bundleID)
        } else {
            excludedBundleIDs.insert(bundleID)
        }
    }
}

/// One row on the Sources screen: an app that has written protein today, what
/// it contributed, and how long ago.
struct ProteinSourceStatus: Sendable, Equatable, Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let grams: Double
    let latestEntry: Date
    let sampleCount: Int
    let isOurs: Bool
    let isIncluded: Bool
    /// Of `grams`, how many are still waiting to reach Apple Health because the
    /// write was denied. Non-zero only on our own row.
    let localOnlyGrams: Double

    init(
        bundleID: String,
        name: String,
        grams: Double,
        latestEntry: Date,
        sampleCount: Int,
        isOurs: Bool,
        isIncluded: Bool,
        localOnlyGrams: Double = 0
    ) {
        self.bundleID = bundleID
        self.name = name
        self.grams = grams
        self.latestEntry = latestEntry
        self.sampleCount = sampleCount
        self.isOurs = isOurs
        self.isIncluded = isIncluded
        self.localOnlyGrams = localOnlyGrams
    }
}

/// Pure, source-grouped reconciliation. No HealthKit, no SwiftUI, no clock of
/// its own — every entry point takes the samples and the selection and returns
/// a value, which is what makes the multi-source cases testable without a
/// device.
enum ProteinReconciliation {
    /// Today's total: every sample from an included source, summed once.
    ///
    /// There is exactly one sum over one set of sources. Our own entries are in
    /// the same set as everyone else's, so there is no "exclude ourselves then
    /// add our own log back" step to get wrong.
    static func total(samples: [ProteinSample], selection: ProteinSourceSelection) -> Double {
        samples.reduce(into: 0.0) { running, sample in
            guard selection.includes(bundleID: sample.sourceBundleID, isOurs: sample.isOurs) else { return }
            running += max(sample.grams, 0)
        }
    }

    /// One row per source that wrote protein in the window, ours first and the
    /// rest by contribution, so the biggest suspect in a double-count sits at
    /// the top of the list.
    ///
    /// The iPhone app and the watch app write under different bundle
    /// identifiers, but they are one app to the person reading this list — so
    /// they collapse into a single row rather than appearing as two entries
    /// with the same name, which reads as exactly the duplication this screen
    /// exists to help the user find.
    static func sources(samples: [ProteinSample], selection: ProteinSourceSelection) -> [ProteinSourceStatus] {
        var grouped: [String: [ProteinSample]] = [:]
        for sample in samples {
            let key = sample.isOurs ? proteinOwnSourceBundleID : sample.sourceBundleID
            grouped[key, default: []].append(sample)
        }

        return grouped.compactMap { bundleID, samples -> ProteinSourceStatus? in
            guard let newest = samples.max(by: { $0.endDate < $1.endDate }) else { return nil }
            let isOurs = samples.contains { $0.isOurs }
            return ProteinSourceStatus(
                bundleID: bundleID,
                name: newest.sourceName,
                grams: samples.reduce(0) { $0 + max($1.grams, 0) },
                latestEntry: newest.endDate,
                sampleCount: samples.count,
                isOurs: isOurs,
                isIncluded: selection.includes(bundleID: bundleID, isOurs: isOurs),
                localOnlyGrams: samples.reduce(0) { $0 + ($1.isLocalOnly ? max($1.grams, 0) : 0) }
            )
        }
        .sorted { lhs, rhs in
            if lhs.isOurs != rhs.isOurs { return lhs.isOurs }
            if lhs.grams != rhs.grams { return lhs.grams > rhs.grams }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// True when two or more *external* apps are both counting today. Two food
    /// loggers writing the same meal is the one way this app can show a
    /// confidently wrong number, so the Sources screen says so out loud rather
    /// than leaving the user to notice the total drifting high.
    static func hasDuplicateRisk(sources: [ProteinSourceStatus]) -> Bool {
        sources.filter { !$0.isOurs && $0.isIncluded && $0.grams > 0 }.count >= 2
    }

    /// Grams still to eat. Never negative — an overshoot is reported by
    /// `overage`, because "-18 g left" reads as an error rather than a result.
    static func remaining(total: Double, target: Double) -> Double {
        max(target - total, 0)
    }

    /// Grams past the target, or zero when still under.
    static func overage(total: Double, target: Double) -> Double {
        max(total - target, 0)
    }

    /// Ring progress. Can exceed 1 so the caller can decide whether to cap the
    /// arc or let it overshoot.
    static func progress(total: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return total / target
    }

    /// Whether the day counts as hit. Half a gram of float drift should not be
    /// the difference between a met target and a missed one.
    static func hasMetTarget(total: Double, target: Double) -> Bool {
        target > 0 && total + 0.5 >= target
    }
}
