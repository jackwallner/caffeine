import Combine
import SwiftUI
import WidgetKit

enum AppAppearance: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Every user-set value, in the App Group so the widgets and the watch read the
/// same store the app writes.
///
/// On the watch this is a local mirror. HealthKit carries the *entries* between
/// devices on its own, but it carries no settings, so the phone pushes the
/// handful of values the wrist needs (target, presets, entitlement) over
/// `WatchSyncService`.
@MainActor
final class GoalSettings: ObservableObject {
    static let shared = GoalSettings()

    @Published var hasCompletedSetup: Bool { didSet { save() } }

    /// Daily target in grams. Normalized on write, so nothing downstream has to
    /// defend against a zero or a negative.
    @Published var targetGrams: Double {
        didSet {
            let normalized = ProteinTargets.normalized(targetGrams)
            if normalized != targetGrams {
                targetGrams = normalized
                return
            }
            save()
            pushToWatch()
        }
    }

    /// Why the user tracks protein, as many as apply. Sets the suggested target
    /// during onboarding and the sentence under it, and is not read anywhere
    /// else.
    ///
    /// Never empty: an empty set would leave the target screen with no sentence
    /// under it, so a cleared selection falls back to the everyday reason.
    @Published var reasons: Set<ProteinReason> {
        didSet {
            if reasons.isEmpty {
                reasons = [.general]
                return
            }
            save()
        }
    }

    /// Last known body weight in kilograms, used only to suggest a target.
    /// Zero when unknown.
    @Published var bodyWeightKilograms: Double { didSet { save() } }

    /// Sources the user has switched off. Opt-out, so a food logger that starts
    /// writing protein tomorrow counts tomorrow.
    ///
    /// Pushed to the wrist like the target is: HealthKit hands both devices the
    /// same samples, so without this the watch would sum a source the phone had
    /// been told to stop counting and quietly disagree with it all day.
    @Published var excludedSourceBundleIDs: Set<String> {
        didSet {
            defaults.set(Array(excludedSourceBundleIDs), forKey: proteinExcludedSourcesKey)
            save()
            pushToWatch()
        }
    }

    /// Display name of each excluded source, keyed by bundle ID. Sources are
    /// listed from today's samples, so an app switched off yesterday that writes
    /// nothing today would otherwise vanish along with the only control that can
    /// switch it back on.
    @Published private(set) var excludedSourceNames: [String: String] {
        didSet {
            defaults.set(excludedSourceNames, forKey: proteinExcludedSourceNamesKey)
        }
    }

    /// The three tunable quick-add buttons, in grams. Present on both the wrist
    /// and the phone, and the whole of the "one tap" promise.
    @Published var quickAddPresets: [Double] {
        didSet {
            defaults.set(quickAddPresets, forKey: proteinPresetsKey)
            save()
            pushToWatch()
        }
    }

    @Published var appearance: AppAppearance { didSet { save() } }

    /// Evening nudge when the day's target is still short. Opt-in.
    @Published var reminderEnabled: Bool { didSet { defaults.set(reminderEnabled, forKey: "reminderEnabled"); save() } }
    @Published var reminderHour: Int { didSet { defaults.set(reminderHour, forKey: "reminderHour"); save() } }

    /// Content version of the last What's New announcement the user has seen.
    @Published var lastWhatsNewVersionShown: String? {
        didSet { defaults.set(lastWhatsNewVersionShown, forKey: "lastWhatsNewVersionShown") }
    }

    /// Published mirror of the cached Protein+ entitlement.
    ///
    /// `ProAccess.isPro` reads the same App Group key, but a plain `UserDefaults`
    /// read cannot drive a SwiftUI update, and a purchase made on the phone
    /// reaches the wrist as a payload whose other fields are usually unchanged.
    /// Nothing on the watch gates on it now that logging is free there — it is
    /// kept because the entitlement still has to arrive on the wrist for
    /// anything paid that lands later, and a mirror that goes stale for a
    /// release is a mirror nobody trusts again.
    @Published private(set) var cachedIsPro: Bool

    static let defaultPresets: [Double] = [25, 30, 40]

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: proteinAppGroupID) ?? .standard
        let completedSetup = defaults.bool(forKey: proteinHasCompletedSetupKey)
        hasCompletedSetup = completedSetup
        targetGrams = defaults.object(forKey: proteinTargetKey) as? Double ?? 140
        // Installs before multi-select stored a single raw value under "reason".
        // Read the set first and fall back to that key, so an upgrade keeps the
        // reason the user picked rather than silently reverting to strength.
        if let stored = defaults.array(forKey: "reasons") as? [Int], !stored.isEmpty {
            let migrated = Set(stored.compactMap(ProteinReason.init(rawValue:)))
            reasons = migrated.isEmpty ? [.strength] : migrated
        } else {
            reasons = [ProteinReason(rawValue: defaults.integer(forKey: "reason")) ?? .strength]
        }
        bodyWeightKilograms = defaults.object(forKey: "bodyWeightKilograms") as? Double ?? 0
        excludedSourceBundleIDs = Set(defaults.stringArray(forKey: proteinExcludedSourcesKey) ?? [])
        excludedSourceNames = defaults.dictionary(forKey: proteinExcludedSourceNamesKey) as? [String: String] ?? [:]
        let storedPresets = defaults.array(forKey: proteinPresetsKey) as? [Double] ?? Self.defaultPresets
        quickAddPresets = storedPresets.count == 3 ? storedPresets : Self.defaultPresets
        appearance = AppAppearance(rawValue: defaults.integer(forKey: "appearance")) ?? .system
        reminderEnabled = defaults.object(forKey: "reminderEnabled") as? Bool ?? false
        reminderHour = defaults.object(forKey: "reminderHour") as? Int ?? 19
        cachedIsPro = ProAccess.isPro
        // Fresh installs are seeded past the What's New announcement so they get
        // onboarding, not a "what changed" pitch for an app they've never used.
        if let stored = defaults.string(forKey: "lastWhatsNewVersionShown") {
            lastWhatsNewVersionShown = stored
        } else if !completedSetup {
            lastWhatsNewVersionShown = WhatsNew.currentVersion
            defaults.set(WhatsNew.currentVersion, forKey: "lastWhatsNewVersionShown")
        } else {
            lastWhatsNewVersionShown = nil
        }
    }

    /// Selected reasons in list order, for display and for storage.
    var orderedReasons: [ProteinReason] { ProteinReason.ordered(reasons) }

    var sourceSelection: ProteinSourceSelection {
        ProteinSourceSelection(excludedBundleIDs: excludedSourceBundleIDs)
    }

    func setSourceIncluded(_ included: Bool, bundleID: String, name: String? = nil) {
        var selection = sourceSelection
        selection.setIncluded(included, bundleID: bundleID)
        if included {
            excludedSourceNames.removeValue(forKey: bundleID)
        } else if let name, !name.isEmpty {
            excludedSourceNames[bundleID] = name
        }
        excludedSourceBundleIDs = selection.excludedBundleIDs
    }

    /// Applies a settings payload received from the paired iPhone. Watch-side
    /// only; the phone is always the writer.
    func apply(_ payload: WatchSettingsPayload) {
        if let target = payload.targetGrams, target != targetGrams {
            targetGrams = ProteinTargets.normalized(target)
        }
        if let presets = payload.quickAddPresets, presets.count == 3, presets != quickAddPresets {
            quickAddPresets = presets
        }
        if let names = payload.excludedSourceNames, names != excludedSourceNames {
            excludedSourceNames = names
        }
        var sourcesChanged = false
        if let excluded = payload.excludedSourceBundleIDs {
            let incoming = Set(excluded)
            if incoming != excludedSourceBundleIDs {
                excludedSourceBundleIDs = incoming
                sourcesChanged = true
            }
        }
        if let isPro = payload.isPro {
            defaults.set(isPro, forKey: proteinCachedProKey)
            // Publish it, or a purchase made on the phone lands silently and the
            // wrist stays locked until relaunch: nothing else in the payload has
            // to change for an entitlement flip.
            if cachedIsPro != ProAccess.isPro {
                cachedIsPro = ProAccess.isPro
            }
        }
        if payload.hasCompletedSetup == true, !hasCompletedSetup {
            hasCompletedSetup = true
        }
        WidgetCenter.shared.reloadAllTimelines()
        // The wrist total comes from the cached day row, which was reconciled
        // against the *old* selection. Without this the exclusion is stored but
        // the number on screen keeps counting the source until something else
        // happens to refresh.
        if sourcesChanged {
            Task { await HealthKitService.shared.refreshCache() }
        }
    }

    /// The payload the phone pushes to the wrist.
    var watchPayload: WatchSettingsPayload {
        WatchSettingsPayload(
            targetGrams: targetGrams,
            quickAddPresets: quickAddPresets,
            isPro: defaults.bool(forKey: proteinCachedProKey),
            hasCompletedSetup: hasCompletedSetup,
            excludedSourceBundleIDs: Array(excludedSourceBundleIDs),
            excludedSourceNames: excludedSourceNames
        )
    }

    private func pushToWatch() {
        #if os(iOS)
        WatchSyncService.shared.push(settings: watchPayload)
        #endif
    }

    private func save() {
        defaults.set(hasCompletedSetup, forKey: proteinHasCompletedSetupKey)
        defaults.set(targetGrams, forKey: proteinTargetKey)
        defaults.set(orderedReasons.map(\.rawValue), forKey: "reasons")
        defaults.set(bodyWeightKilograms, forKey: "bodyWeightKilograms")
        defaults.set(appearance.rawValue, forKey: "appearance")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
