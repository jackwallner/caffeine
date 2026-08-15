import SwiftData
import SwiftUI
import WatchKit

@main
struct ProteinWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    init() {
        #if DEBUG
        if ScreenshotConfig.isEnabled {
            // Keep the wrist capture on the same target as the seeded samples
            // and the phone capture. The watch has its own App Group defaults,
            // so the phone's screenshot setup cannot do this for it.
            GoalSettings.shared.targetGrams = ScreenshotFixtures.target
            GoalSettings.shared.hasCompletedSetup = true
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchTodayView() }
        }
        .modelContainer(DataService.sharedModelContainer)
    }
}

/// Background refresh plumbing.
///
/// The HealthKit observer on watchOS deliberately does no work in its callback —
/// the CAROUSEL watchdog has a tight CPU budget — so it schedules a background
/// refresh and the real reconcile happens here, where the system has granted a
/// protected window for it.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchSyncService.shared.start()
        Task { @MainActor in
            await HealthKitService.shared.synchronizeAuthorization()
            // The wrist has its own write-denied fallback rows, and its own App
            // Group, so nothing on the phone can rescue them. Retry here for the
            // same reason the phone retries on foreground: once the user allows
            // writes, grams stranded on this device belong in HealthKit, which
            // is the only thing that carries them to the other device.
            await ProteinLogService.shared.retryPendingLocalEntries()
            await HealthKitService.shared.refreshCache()
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
                    await ProteinLogService.shared.retryPendingLocalEntries()
                    await HealthKitService.shared.refreshCache()
                    refreshTask.setTaskCompletedWithSnapshot(false)
                }
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                snapshotTask.setTaskCompleted(
                    restoredDefaultState: true,
                    estimatedSnapshotExpiration: .distantFuture,
                    userInfo: nil
                )
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
