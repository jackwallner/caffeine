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

    /// Why the user tracks protein. Sets the suggested target during onboarding
    /// and the sentence under it, and is not read anywhere else.
    @Published var reason: ProteinReason { didSet { save() } }

    /// Last known body weight in kilograms, used only to suggest a target.
    /// Zero when unknown.
    @Published var bodyWeightKilograms: Double { didSet { save() } }

    /// Sources the user has switched off. Opt-out, so a food logger that starts
    /// writing protein tomorrow counts tomorrow.
    @Published var excludedSourceBundleIDs: Set<String> {
        didSet {
            defaults.set(Array(excludedSourceBundleIDs), forKey: proteinExcludedSourcesKey)
            save()
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

    /// Published mirror of the cached Protein+ entitlement, for the watch.
    ///
    /// `ProAccess.isPro` reads the same App Group key, but a plain `UserDefaults`
    /// read cannot drive a SwiftUI update. A purchase made on the phone reaches
    /// the wrist as a settings payload whose other fields are usually unchanged,
    /// so without a publisher here the watch keeps showing the locked notice
    /// until it is next launched. The phone reads `StoreService.isPro` directly
    /// and never needs this.
    @Published private(set) var cachedIsPro: Bool

    static let defaultPresets: [Double] = [25, 30, 40]

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: proteinAppGroupID) ?? .standard
        let completedSetup = defaults.bool(forKey: proteinHasCompletedSetupKey)
        hasCompletedSetup = completedSetup
        targetGrams = defaults.object(forKey: proteinTargetKey) as? Double ?? 140
        reason = ProteinReason(rawValue: defaults.integer(forKey: "reason")) ?? .strength
        bodyWeightKilograms = defaults.object(forKey: "bodyWeightKilograms") as? Double ?? 0
        excludedSourceBundleIDs = Set(defaults.stringArray(forKey: proteinExcludedSourcesKey) ?? [])
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

    var sourceSelection: ProteinSourceSelection {
        ProteinSourceSelection(excludedBundleIDs: excludedSourceBundleIDs)
    }

    func setSourceIncluded(_ included: Bool, bundleID: String) {
        var selection = sourceSelection
        selection.setIncluded(included, bundleID: bundleID)
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
    }

    /// The payload the phone pushes to the wrist.
    var watchPayload: WatchSettingsPayload {
        WatchSettingsPayload(
            targetGrams: targetGrams,
            quickAddPresets: quickAddPresets,
            isPro: defaults.bool(forKey: proteinCachedProKey),
            hasCompletedSetup: hasCompletedSetup
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
        defaults.set(reason.rawValue, forKey: "reason")
        defaults.set(bodyWeightKilograms, forKey: "bodyWeightKilograms")
        defaults.set(appearance.rawValue, forKey: "appearance")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
