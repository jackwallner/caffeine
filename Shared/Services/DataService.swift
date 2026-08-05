import Foundation
import os
import SwiftData

let proteinAppGroupID = "group.com.jackwallner.protein"

/// App Group key mirroring the live `isPro` entitlement, written by
/// `StoreService` and read by the widgets and the watch app. Defined here (not
/// on StoreService) so it is reachable from targets that exclude StoreService,
/// which is every target except the iPhone app.
let proteinCachedProKey = "isPro"

/// App Group keys the widgets, the complication, and the WatchConnectivity
/// payload all read. Module-level rather than static members of `GoalSettings`,
/// which is `@MainActor` and therefore unreachable from a `WCSession` delegate
/// callback or a widget timeline provider.
let proteinTargetKey = "targetGrams"
let proteinPresetsKey = "quickAddPresets"
let proteinExcludedSourcesKey = "excludedSourceBundleIDs"
let proteinHasCompletedSetupKey = "hasCompletedSetup"

/// Bundle identifier of our own HealthKit source. Samples carrying this are
/// ours: they can never be excluded on the Sources screen, and they are what
/// "Protein Tracker · 4m ago" is reporting on.
let proteinOwnSourceBundleID = "com.jackwallner.protein"

/// Our own samples arrive from either device under one of these bundle IDs, so
/// wrist entries are recognised as ours on the phone and vice versa.
let proteinOwnSourceBundleIDs: Set<String> = [
    "com.jackwallner.protein",
    "com.jackwallner.protein.watch",
]

@MainActor
enum DataService {
    static let appGroupID = proteinAppGroupID

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([DailyProteinRecord.self, LocalProteinEntry.self])
        let storeURL = containerURL.appendingPathComponent("Protein.store")
        let configuration = ModelConfiguration(
            "Protein",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            Logger(subsystem: "com.jackwallner.protein", category: "Data")
                .error("Persistent store failed: \(String(describing: error), privacy: .public)")
            let fallback = ModelConfiguration(
                "ProteinFallback",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Unable to initialize Protein data store: \(error)")
            }
        }
    }()

    private static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
}

/// Entitlement read that works in every target.
///
/// The widgets and the watch app need to know whether Protein+ is active, but
/// they do not link RevenueCat. `StoreService` mirrors the live entitlement
/// into the App Group on every change; this is the read side of that mirror.
enum ProAccess {
    static var isPro: Bool {
        (UserDefaults(suiteName: proteinAppGroupID) ?? .standard).bool(forKey: proteinCachedProKey)
    }
}
