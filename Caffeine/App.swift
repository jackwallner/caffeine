import SwiftData
import SwiftUI

@main
struct CaffeineApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = CaffeineSettings.shared
    @StateObject private var store = StoreService.shared

    init() {
        WatchSyncService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .preferredColorScheme(settings.appearance.colorScheme)
                .task {
                    store.start()
                    #if DEBUG
                    if ScreenshotConfig.isEnabled {
                        settings.hasCompletedSetup = true
                        settings.bedtimeMinutes = 22 * 60 + 30
                        settings.halfLifeHours = 5
                        settings.bedtimeThreshold = 25
                    }
                    #endif
                    await HealthKitService.shared.synchronizeAuthorization()
                    await HealthKitService.shared.refreshCache()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await CaffeineLogService.shared.retryPendingLocalEntries()
                        await HealthKitService.shared.refreshCache()
                    }
                }
        }
        .modelContainer(DataService.sharedModelContainer)
    }
}

private struct RootView: View {
    @EnvironmentObject private var settings: CaffeineSettings

    var body: some View {
        if Self.paywallSnapshot {
            CaffeinePurchaseView()
        } else if !settings.hasCompletedSetup && !ScreenshotConfig.isEnabled {
            CaffeineOnboardingView()
        } else {
            CaffeineTabView(initialTab: Self.screenshotTab ?? 0)
        }
    }

    static var paywallSnapshot: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PaywallSnapshot")
        #else
        false
        #endif
    }

    static var screenshotTab: Int? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ScreenshotTab"), index + 1 < arguments.count else {
            return nil
        }
        return Int(arguments[index + 1])
        #else
        return nil
        #endif
    }
}

struct CaffeineTabView: View {
    let initialTab: Int
    @State private var selection: Int

    init(initialTab: Int = 0) {
        self.initialTab = initialTab
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { CaffeineNowView() }
                .tabItem { Label("Now", systemImage: "waveform.path.ecg") }
                .tag(0)
            NavigationStack { CaffeineTimelineView() }
                .tabItem { Label("Timeline", systemImage: "clock.arrow.circlepath") }
                .tag(1)
            NavigationStack { CaffeinePlannerView() }
                .tabItem { Label("Planner", systemImage: "moon.stars.fill") }
                .tag(2)
            NavigationStack { CaffeineSettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(3)
        }
        .tint(Theme.violet)
    }
}
