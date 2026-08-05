import SwiftData
import SwiftUI
import WatchKit

@main
struct ProteinWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

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
            await HealthKitService.shared.refreshCache()
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
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
