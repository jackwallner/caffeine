import SwiftData
import SwiftUI

@main
struct ProteinApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = GoalSettings.shared
    @StateObject private var store = StoreService.shared

    init() {
        // `App.init()` is main-actor isolated, so the @MainActor trackers are
        // safe to touch here.
        ReviewPromptTracker.recordAppLaunch()
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
                        // Match the seeded samples, so a capture shows a real
                        // "36 g left" rather than fixtures against whatever
                        // target the last run happened to leave behind.
                        settings.targetGrams = ScreenshotFixtures.target
                        settings.hasCompletedSetup = true
                    }
                    #endif
                    await HealthKitService.shared.synchronizeAuthorization()
                    await HealthKitService.shared.refreshCache()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        // Always refresh on foreground: "no data" and "denied"
                        // are indistinguishable for reads, so gating on
                        // isAuthorized would blank the screen after a flaky
                        // launch-time probe. refreshCache self-guards the
                        // never-authorized case.
                        await ProteinLogService.shared.retryPendingLocalEntries()
                        await HealthKitService.shared.refreshCache()
                    }
                }
        }
        .modelContainer(DataService.sharedModelContainer)
    }
}

private struct RootView: View {
    @EnvironmentObject private var settings: GoalSettings

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-PaywallSnapshot") {
            PaywallView()
        } else if Self.screenshotTab != nil {
            // DEBUG-only capture hook: jump straight into the tab bar on a
            // chosen tab, bypassing onboarding, so App Store screenshots can be
            // taken without UI automation. Never triggers in Release.
            MainTabView(initialTab: Self.screenshotTab ?? 0)
        } else if !settings.hasCompletedSetup {
            // Onboarding is the root view, not a sheet, so pages simply exist
            // instead of swiping up from the bottom. The trial pitch is folded
            // in as the final onboarding step (zero-shift CTA), so there is no
            // separate pop-up after setup.
            OnboardingView()
        } else {
            MainTabView()
        }
    }

    /// DEBUG-only: `-ScreenshotTab N` (0 Today, 1 History, 2 Settings) opens
    /// that tab with onboarding skipped. nil in Release.
    static var screenshotTab: Int? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-ScreenshotTab"), idx + 1 < args.count else { return nil }
        return Int(args[idx + 1])
        #else
        return nil
        #endif
    }
}

private struct MainTabView: View {
    var initialTab: Int = 0

    @EnvironmentObject private var settings: GoalSettings
    @EnvironmentObject private var store: StoreService
    @StateObject private var reviewPromptCoordinator = ReviewPromptCoordinator.shared
    @Environment(\.requestReview) private var requestReview

    @State private var selection = 0

    // What's New
    @State private var showWhatsNew = false
    @State private var whatsNewEvaluated = false
    @State private var showPaywallFromWhatsNew = false
    @State private var pendingPaywallAfterWhatsNew = false

    // Review funnel
    @State private var showReviewPrompt = false
    @State private var reviewPromptInitialStep: ReviewPromptSheet.Step = .enjoyment
    @State private var reviewPromptShownThisSession = false

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent(tab: 0) { TodayView() }
            tabContent(tab: 1) { HistoryView() }
            tabContent(tab: 2) { SettingsView() }

            HStack(spacing: 0) {
                TabButton(icon: "bolt.fill", label: "Today", isSelected: selection == 0) { selection = 0 }
                TabButton(icon: "chart.bar.fill", label: "History", isSelected: selection == 1) { selection = 1 }
                TabButton(icon: "gearshape.fill", label: "Settings", isSelected: selection == 2) { selection = 2 }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial.opacity(0.8), in: Capsule())
            .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
            .padding(.bottom, 12)
        }
        .ignoresSafeArea(edges: .bottom)
        .tint(Theme.protein)
        .onAppear {
            selection = initialTab
            evaluateWhatsNew()
            evaluatePendingReviewPrompt()
        }
        .onChange(of: reviewPromptCoordinator.pendingPresentation) { _, presentation in
            guard let presentation else { return }
            defer { reviewPromptCoordinator.clear() }
            switch presentation {
            case .enjoymentPrompt: presentReviewPrompt(step: .enjoyment)
            case .feedbackOnly: presentReviewPrompt(step: .feedback)
            }
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: {
            if pendingPaywallAfterWhatsNew {
                pendingPaywallAfterWhatsNew = false
                showPaywallFromWhatsNew = true
            }
        }) {
            WhatsNewSheet(
                isPro: store.isPro,
                // Neutral for the same 3.1.2(c) reason as the purchase CTAs:
                // this routes into the paywall, so it must not pitch the trial
                // ahead of the price the paywall is about to state.
                tryFreeCTATitle: "Explore Protein+",
                onTryFree: { pendingPaywallAfterWhatsNew = true; showWhatsNew = false },
                onOpenSettings: { showWhatsNew = false; selection = 2 },
                onDismiss: { showWhatsNew = false }
            )
        }
        .sheet(isPresented: $showPaywallFromWhatsNew) {
            PaywallView().environmentObject(store)
        }
        .sheet(isPresented: $showReviewPrompt, onDismiss: {
            if reviewPromptCoordinator.pendingPresentation == nil,
               ReviewPromptTracker.outcome == nil,
               ReviewPromptTracker.isSoftDeferred {
                // "Maybe later": Apple often no-ops requestReview(), so we keep
                // a short cooldown rather than the long jail markShown() sets.
                requestReview()
            }
        }) {
            ReviewPromptSheet(initialStep: reviewPromptInitialStep) { _ in
                showReviewPrompt = false
            }
        }
    }

    private func evaluateWhatsNew() {
        guard !whatsNewEvaluated,
              settings.hasCompletedSetup,
              !ScreenshotConfig.isEnabled,
              WhatsNew.shouldShow(lastShown: settings.lastWhatsNewVersionShown),
              !showReviewPrompt else { return }
        whatsNewEvaluated = true
        settings.lastWhatsNewVersionShown = WhatsNew.currentVersion
        showWhatsNew = true
    }

    private func evaluatePendingReviewPrompt() {
        guard !reviewPromptShownThisSession, !showReviewPrompt, !showWhatsNew else { return }
        guard ReviewPromptTracker.shouldShowPassively(hasCompletedSetup: settings.hasCompletedSetup) else { return }
        ReviewPromptTracker.consumePendingMoment()
        presentReviewPrompt(step: .enjoyment)
    }

    private func presentReviewPrompt(step: ReviewPromptSheet.Step) {
        reviewPromptInitialStep = step
        reviewPromptShownThisSession = true
        showReviewPrompt = true
    }

    /// All three tabs stay alive in the `ZStack` so each keeps its own scroll
    /// position. The hidden two are also kept out of the accessibility tree —
    /// note the `accessibilityHidden` applied to the tab's root *inside* the
    /// `NavigationStack` as well as to the stack itself: the outer one alone
    /// does not reach the stack's hosted content, so VoiceOver would otherwise
    /// walk all three tabs' worth of elements before reaching the one on screen.
    private func tabContent<Content: View>(
        tab: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .environment(\.isActiveTab, selection == tab)
                .accessibilityHidden(selection != tab)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 92)
        }
        .tabVisibility(selection == tab)
    }
}

/// Whether the tab this view sits in is the one on screen. All three tabs are
/// built and kept alive at launch, so anything with a side effect on appearance
/// — a paywall logging an impression — has to ask, or it fires for tabs the
/// user never opened.
private struct IsActiveTabKey: EnvironmentKey {
    /// Views outside the tab stack (sheets, previews) are always "on screen".
    static let defaultValue = true
}

extension EnvironmentValues {
    var isActiveTab: Bool {
        get { self[IsActiveTabKey.self] }
        set { self[IsActiveTabKey.self] = newValue }
    }
}

private extension View {
    func tabVisibility(_ isVisible: Bool) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}

private struct TabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? Theme.protein : Color(.tertiaryLabel))
            .frame(width: 72, height: 44)
            .background(
                isSelected ? Theme.protein.opacity(0.12) : .clear,
                in: Capsule()
            )
            // Without a content shape the tap area shrinks to the icon and
            // label, which reports a target well under 44pt.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        // Without this VoiceOver reads all three tabs identically and never
        // says which one you are on.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
