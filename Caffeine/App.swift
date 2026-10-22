import SwiftData
import SwiftUI

@main
struct CaffeineApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = CaffeineSettings.shared
    @StateObject private var store = StoreService.shared

    init() {
        WatchSyncService.shared.start()
        ConversionDiagnostics.recordAppOpen()
        #if DEBUG
        if RevenueCatProbe.isEnabled {
            // The impression hook needs a configured SDK, and configure happens
            // in `start()`, so the probe does that first. After it, this is the
            // same entry point the real paywall screens call.
            StoreService.shared.start()
            StoreService.shared.trackPaywallImpression(id: RevenueCatProbe.impressionID)
            if RevenueCatProbe.wantsPurchase {
                Task { await StoreService.shared.runProbePurchase() }
            }
        }
        #endif
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
                        settings.bodyInsightsEnabled = true
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
                        if settings.bodyInsightsEnabled {
                            await HealthInsightsService.shared.refresh()
                        }
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
            CaffeinePaywallView()
        } else if let startTab = Self.startTab {
            CaffeineTabView(initialTab: startTab)
        } else if !settings.hasCompletedSetup && !ScreenshotConfig.isEnabled {
            CaffeineOnboardingView()
        } else {
            CaffeineTabView(initialTab: Self.screenshotTab ?? 0)
        }
    }

    /// Opens straight onto a tab without entering screenshot mode, so a headless
    /// run can inspect a live surface (the Upgrade tab in particular, which
    /// screenshot mode empties of products) rather than a fixture of one.
    static var startTab: Int? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-StartTab"), index + 1 < arguments.count else {
            return nil
        }
        return Int(arguments[index + 1])
        #else
        return nil
        #endif
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

/// Four tabs. Settings moved to a gear on Now, matching the rest of the fleet,
/// and the old Planner tab folded into the drink preview, which was already
/// doing the same job from the Now screen.
///
/// Upgrade is a tab rather than only a sheet so the purchase surface is always
/// one tap away and a subscriber has a permanent place to manage what they
/// bought. The tab bar stays visible over it, so nothing traps the user on a
/// purchase screen.
///
/// Unfolded on iPhone Duo, Your Cutoff leaves the tab bar and takes the pane on
/// the trailing side of the fold, so the bedtime forecast on Now is read beside
/// the cutoff from this person's own nights. The tab bar and the other tabs stay
/// on the leading side. Folding only moves frames, so Now, Timeline and Upgrade
/// keep their state.
struct CaffeineTabView: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let initialTab: Int
    @State private var selection: Int
    @State private var paneGeometry = PaneGeometry(width: 0, fold: nil)

    init(initialTab: Int = 0) {
        self.initialTab = initialTab
        _selection = State(initialValue: initialTab)
    }

    private var split: UnfoldedSplit? {
        UnfoldedSplit.make(
            width: paneGeometry.width,
            isRegularWidth: horizontalSizeClass == .regular,
            fold: paneGeometry.fold
        )
    }

    /// Each unfolded pane is phone-width, so its screen lays out as on a phone.
    private var paneSizeClass: UserInterfaceSizeClass? {
        split == nil ? horizontalSizeClass : .compact
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TabView(selection: $selection) {
                NavigationStack { CaffeineNowView() }
                    .tabItem { Label("Now", systemImage: "waveform.path.ecg") }
                    .tag(0)
                if split == nil {
                    NavigationStack { BodyInsightsView() }
                        .tabItem { Label("Cutoff", systemImage: "moon.stars.fill") }
                        .tag(1)
                }
                NavigationStack { CaffeineTimelineView() }
                    .tabItem { Label("Timeline", systemImage: "clock.arrow.circlepath") }
                    .tag(2)
                NavigationStack {
                    CaffeinePaywallView(
                        displayCloseButton: false,
                        paywallImpressionID: "caffeine_upgrade_tab"
                    )
                    .navigationTitle(store.isPro ? "Caffeine+" : "Upgrade")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem {
                    Label(
                        store.isPro ? "Caffeine+" : "Upgrade",
                        systemImage: store.isPro ? "sparkles" : "lock.fill"
                    )
                }
                .tag(3)
            }
            .tint(Theme.violet)
            .environment(\.horizontalSizeClass, paneSizeClass)
            .frame(maxWidth: split?.primaryWidth ?? .infinity, maxHeight: .infinity)

            if let split {
                NavigationStack { BodyInsightsView() }
                    .tint(Theme.violet)
                    .environment(\.horizontalSizeClass, .compact)
                    .frame(maxWidth: split.secondaryWidth, maxHeight: .infinity)
                    .padding(.leading, split.secondaryX)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onGeometryChange(for: PaneGeometry.self) { proxy in
            PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
        } action: { paneGeometry = $0 }
        .onChange(of: split != nil) { _, isSplit in
            if isSplit, selection == 1 { selection = 0 }
        }
        .onChange(of: selection) { _, tab in
            // Launch routes and capture links can still ask for the Cutoff tab.
            if tab == 1, split != nil { selection = 0 }
        }
        #if DEBUG
        .onOpenURL { openCaptureRoute($0) }
        #endif
    }

    #if DEBUG
    /// Capture runs step through the surfaces with links the simulator can open
    /// between screenshots: `caffeine-capture://tab/2` selects a tab and
    /// `caffeine-capture://preview` opens the drink preview on Now.
    private func openCaptureRoute(_ url: URL) {
        guard url.scheme == "caffeine-capture" else { return }
        switch url.host {
        case "tab":
            selection = Int(url.lastPathComponent) ?? 0
        case "preview":
            selection = 0
            NotificationCenter.default.post(name: .caffeineCapturePreview, object: nil)
        default:
            break
        }
    }
    #endif
}

#if DEBUG
extension Notification.Name {
    static let caffeineCapturePreview = Notification.Name("caffeineCapturePreview")
}
#endif
