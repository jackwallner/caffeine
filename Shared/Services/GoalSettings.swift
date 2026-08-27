import Combine
import SwiftUI
import WidgetKit

enum AppAppearance: Int, CaseIterable {
    case system
    case light
    case dark

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

@MainActor
final class CaffeineSettings: ObservableObject {
    static let shared = CaffeineSettings()
    static let defaultPresets = [80.0, 120.0, 200.0]

    @Published var hasCompletedSetup: Bool { didSet { persistAndSync() } }
    @Published var bedtimeMinutes: Int { didSet { persistAndSync() } }
    @Published var halfLifeHours: Double { didSet { persistAndSync() } }
    @Published var bedtimeThreshold: Double { didSet { persistAndSync() } }
    @Published var quickAddPresets: [Double] { didSet { persistAndSync() } }
    @Published var excludedSourceBundleIDs: Set<String> { didSet { persistAndSync() } }
    @Published private(set) var excludedSourceNames: [String: String]
    @Published var appearance: AppAppearance { didSet { persistAndSync() } }
    @Published var reminderEnabled: Bool { didSet { persistAndSync() } }
    @Published var cachedIsPro: Bool

    private let defaults: UserDefaults
    private var isInitializing = true

    private init() {
        defaults = UserDefaults(suiteName: caffeineAppGroupID) ?? .standard
        hasCompletedSetup = defaults.bool(forKey: caffeineHasCompletedSetupKey)
        bedtimeMinutes = defaults.object(forKey: caffeineBedtimeMinutesKey) as? Int ?? 22 * 60 + 30
        halfLifeHours = defaults.object(forKey: caffeineHalfLifeKey) as? Double ?? 5
        bedtimeThreshold = defaults.object(forKey: caffeineThresholdKey) as? Double ?? 25
        let presets = defaults.array(forKey: caffeinePresetsKey) as? [Double] ?? Self.defaultPresets
        quickAddPresets = presets.count == 3 ? presets : Self.defaultPresets
        excludedSourceBundleIDs = Set(defaults.stringArray(forKey: caffeineExcludedSourcesKey) ?? [])
        excludedSourceNames = defaults.dictionary(forKey: caffeineExcludedSourceNamesKey) as? [String: String] ?? [:]
        appearance = AppAppearance(rawValue: defaults.integer(forKey: "appearance")) ?? .system
        reminderEnabled = defaults.bool(forKey: "reminderEnabled")
        cachedIsPro = ProAccess.isPro
        isInitializing = false
    }

    var sourceSelection: CaffeineSourceSelection {
        CaffeineSourceSelection(excludedBundleIDs: excludedSourceBundleIDs)
    }

    var bedtimeDate: Date {
        bedtime(onOrAfter: .now)
    }

    func bedtime(onOrAfter date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let candidate = calendar.date(byAdding: .minute, value: bedtimeMinutes, to: start) ?? date
        if candidate > date { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
    }

    func setSourceIncluded(_ included: Bool, bundleID: String, name: String) {
        if included {
            excludedSourceBundleIDs.remove(bundleID)
            excludedSourceNames.removeValue(forKey: bundleID)
        } else {
            excludedSourceBundleIDs.insert(bundleID)
            excludedSourceNames[bundleID] = name
        }
        defaults.set(excludedSourceNames, forKey: caffeineExcludedSourceNamesKey)
    }

    func apply(_ payload: WatchSettingsPayload) {
        if let value = payload.bedtimeMinutes { bedtimeMinutes = value }
        if let value = payload.halfLifeHours { halfLifeHours = value }
        if let value = payload.bedtimeThreshold { bedtimeThreshold = value }
        if let value = payload.quickAddPresets, value.count == 3 { quickAddPresets = value }
        if let value = payload.excludedSourceBundleIDs { excludedSourceBundleIDs = Set(value) }
        if let value = payload.excludedSourceNames {
            excludedSourceNames = value
            defaults.set(value, forKey: caffeineExcludedSourceNamesKey)
        }
        if let value = payload.isPro {
            defaults.set(value, forKey: caffeineCachedProKey)
            cachedIsPro = value
        }
        if payload.hasCompletedSetup == true { hasCompletedSetup = true }
        WidgetCenter.shared.reloadAllTimelines()
    }

    var watchPayload: WatchSettingsPayload {
        WatchSettingsPayload(
            bedtimeMinutes: bedtimeMinutes,
            halfLifeHours: halfLifeHours,
            bedtimeThreshold: bedtimeThreshold,
            quickAddPresets: quickAddPresets,
            isPro: ProAccess.isPro,
            hasCompletedSetup: hasCompletedSetup,
            excludedSourceBundleIDs: Array(excludedSourceBundleIDs),
            excludedSourceNames: excludedSourceNames
        )
    }

    private func persistAndSync() {
        guard !isInitializing else { return }
        defaults.set(hasCompletedSetup, forKey: caffeineHasCompletedSetupKey)
        defaults.set(bedtimeMinutes, forKey: caffeineBedtimeMinutesKey)
        defaults.set(halfLifeHours, forKey: caffeineHalfLifeKey)
        defaults.set(bedtimeThreshold, forKey: caffeineThresholdKey)
        defaults.set(quickAddPresets, forKey: caffeinePresetsKey)
        defaults.set(Array(excludedSourceBundleIDs), forKey: caffeineExcludedSourcesKey)
        defaults.set(appearance.rawValue, forKey: "appearance")
        defaults.set(reminderEnabled, forKey: "reminderEnabled")
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        WatchSyncService.shared.push(settings: watchPayload)
        #endif
    }
}
