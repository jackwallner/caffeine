import Foundation
import os
import WatchConnectivity

private let watchSyncLogger = Logger(subsystem: "com.jackwallner.protein", category: "WatchSync")

/// The settings the wrist needs from the phone, as a `Sendable` value.
///
/// WatchConnectivity speaks `[String: Any]`, which cannot cross an actor
/// boundary, so the dictionary is decoded on the delivering thread and this is
/// what travels to the main actor.
struct WatchSettingsPayload: Sendable, Equatable {
    var targetGrams: Double?
    var quickAddPresets: [Double]?
    var isPro: Bool?
    var hasCompletedSetup: Bool?

    init(targetGrams: Double?, quickAddPresets: [Double]?, isPro: Bool?, hasCompletedSetup: Bool?) {
        self.targetGrams = targetGrams
        self.quickAddPresets = quickAddPresets
        self.isPro = isPro
        self.hasCompletedSetup = hasCompletedSetup
    }

    /// Returns nil when the context carries nothing we recognise, so an empty
    /// or foreign payload never triggers a pointless main-actor hop.
    init?(context: [String: Any]) {
        let target = context[proteinTargetKey] as? Double
        let presets = context[proteinPresetsKey] as? [Double]
        let isPro = context[proteinCachedProKey] as? Bool
        let completed = context[proteinHasCompletedSetupKey] as? Bool
        guard target != nil || presets != nil || isPro != nil || completed != nil else { return nil }
        self.init(targetGrams: target, quickAddPresets: presets, isPro: isPro, hasCompletedSetup: completed)
    }

    var dictionary: [String: Any] {
        var context: [String: Any] = [:]
        if let targetGrams { context[proteinTargetKey] = targetGrams }
        if let quickAddPresets { context[proteinPresetsKey] = quickAddPresets }
        if let isPro { context[proteinCachedProKey] = isPro }
        if let hasCompletedSetup { context[proteinHasCompletedSetupKey] = hasCompletedSetup }
        return context
    }
}

/// One-way settings mirror, iPhone → Apple Watch.
///
/// Deliberately *not* a write queue for entries. Logged grams go straight into
/// HealthKit, which syncs across the paired devices on its own, which is what
/// lets this app skip the whole ordering-and-retry problem (`docs/plan.md` §4).
/// What HealthKit does not carry is settings, so the target, the quick-add
/// presets, and the entitlement come across here — a single `applicationContext`
/// dictionary, which the system delivers as latest-value-wins and re-delivers
/// on reconnect. Nothing here can lose a user's data if it fails; it just means
/// the wrist shows a stale target until the next launch.
final class WatchSyncService: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSyncService()

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #if os(watchOS)
        // A context that arrived while the app was not running is waiting on
        // the session as soon as it activates.
        applyReceivedContext(session.receivedApplicationContext)
        #endif
    }

    #if os(iOS)
    /// Latest-value-wins. Failure is not worth surfacing: the next settings
    /// change or the next watch launch re-sends the whole payload.
    func push(settings: WatchSettingsPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            session.delegate = self
            session.activate()
            return
        }
        // Gate on `isPaired`, not `isWatchAppInstalled`: the latter is false
        // during the window where the watch app is still installing, and a
        // context pushed then is exactly the one a fresh watch needs.
        guard session.isPaired else { return }
        do {
            try session.updateApplicationContext(settings.dictionary)
        } catch {
            watchSyncLogger.error("Watch settings push failed: \(String(describing: error), privacy: .public)")
        }
    }
    #endif

    /// Decodes on the delivering thread and hands a `Sendable` value across the
    /// actor hop — a raw `[String: Any]` cannot cross one, and boxing it away
    /// with `@unchecked` would only hide the same race.
    private func applyReceivedContext(_ context: [String: Any]) {
        guard let payload = WatchSettingsPayload(context: context) else { return }
        Task { @MainActor in
            GoalSettings.shared.apply(payload)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            watchSyncLogger.error("Session activation failed: \(String(describing: error), privacy: .public)")
            return
        }
        #if os(watchOS)
        applyReceivedContext(session.receivedApplicationContext)
        #else
        // Push current settings as soon as the session is usable so a freshly
        // installed watch app is not sitting on defaults.
        Task { @MainActor in
            self.push(settings: GoalSettings.shared.watchPayload)
        }
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyReceivedContext(applicationContext)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a watch swap keeps receiving settings.
        WCSession.default.activate()
    }

    /// Re-push on pairing changes: a watch that has just had the app installed
    /// has never seen a context.
    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.push(settings: GoalSettings.shared.watchPayload)
        }
    }
    #endif
}
