import Foundation

/// How the user last resolved the in-app review / feedback prompt.
enum ReviewPromptOutcome: String, Sendable {
    /// Opened the App Store write-review page (explicit CTA).
    case openedWriteReview
    /// Opened the feedback mail composer with a message.
    case submittedFeedback
}

/// Pure eligibility rules for the enjoyment funnel, kept free of `UserDefaults`
/// so the thresholds can be unit-tested directly.
///
/// The trigger is the third *day* the user hit their target, not the third tap
/// or the third launch. Hitting a protein target three separate days is the
/// clearest signal available that the app is doing its job, and it cannot be
/// reached by someone who opened the app twice and never used it.
struct ReviewPromptEligibility: Sendable {
    /// Distinct calendar days on which the target was met.
    var targetHitDays: Int
    /// Cold starts since install.
    var appLaunchCount: Int
    /// Whole days since the first app open.
    var daysSinceFirstOpen: Int

    static let minimumTargetHitDays = 3
    static let minimumLaunchCount = 3
    static let minimumDaysSinceFirstOpen = 3

    var isEligible: Bool {
        targetHitDays >= Self.minimumTargetHitDays
            && appLaunchCount >= Self.minimumLaunchCount
            && daysSinceFirstOpen >= Self.minimumDaysSinceFirstOpen
    }
}

/// Persists launch counts, target-hit days, and review-prompt eligibility in the
/// app group.
@MainActor
enum ReviewPromptTracker {
    private static let defaults = UserDefaults(suiteName: proteinAppGroupID) ?? .standard

    private static let launchCountKey = "reviewPrompt.appLaunchCount"
    private static let firstOpenKey = "reviewPrompt.firstAppOpenDate"
    private static let lastShownKey = "reviewPrompt.lastShownDate"
    private static let outcomeKey = "reviewPrompt.outcome"
    private static let targetHitDaysKey = "reviewPrompt.targetHitDays"
    private static let pendingMomentKey = "reviewPrompt.pendingMoment"
    private static let softDeferKey = "reviewPrompt.softDefer"

    /// Days before "Not now" can surface the enjoyment prompt again.
    static let cooldownDays = 120
    /// Shorter cooldown after "Maybe later" on the review pitch — Apple's
    /// `requestReview()` often shows nothing, so a 120-day jail burns asks.
    static let softDeferCooldownDays = 30

    static var appLaunchCount: Int {
        get { max(defaults.integer(forKey: launchCountKey), 0) }
        set { defaults.set(newValue, forKey: launchCountKey) }
    }

    static var firstAppOpenDate: Date? {
        get { defaults.object(forKey: firstOpenKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: firstOpenKey)
            } else {
                defaults.removeObject(forKey: firstOpenKey)
            }
        }
    }

    static var lastShownDate: Date? {
        get { defaults.object(forKey: lastShownKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: lastShownKey)
            } else {
                defaults.removeObject(forKey: lastShownKey)
            }
        }
    }

    static var outcome: ReviewPromptOutcome? {
        get {
            guard let raw = defaults.string(forKey: outcomeKey) else { return nil }
            return ReviewPromptOutcome(rawValue: raw)
        }
        set {
            if let value = newValue {
                defaults.set(value.rawValue, forKey: outcomeKey)
            } else {
                defaults.removeObject(forKey: outcomeKey)
            }
        }
    }

    /// Day keys on which the target was met. Stored as keys rather than a count
    /// so a day that is refreshed twenty times still counts once.
    private static var targetHitDayKeys: Set<String> {
        get { Set(defaults.stringArray(forKey: targetHitDaysKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: targetHitDaysKey) }
    }

    static var targetHitDays: Int { targetHitDayKeys.count }

    /// Set when a new target-hit day is recorded; cleared when a prompt is shown.
    static var hasPendingMoment: Bool {
        get { defaults.bool(forKey: pendingMomentKey) }
        set { defaults.set(newValue, forKey: pendingMomentKey) }
    }

    /// Call once per process launch.
    static func recordAppLaunch(now: Date = .now) {
        if firstAppOpenDate == nil {
            firstAppOpenDate = now
        }
        appLaunchCount += 1
    }

    /// Call whenever a refresh finds the day's target met. Idempotent within a
    /// day.
    static func recordTargetHit(now: Date = .now) {
        let key = DateHelpers.dayKey(for: now)
        var keys = targetHitDayKeys
        guard !keys.contains(key) else { return }
        keys.insert(key)
        targetHitDayKeys = keys
        hasPendingMoment = true
    }

    static func consumePendingMoment() {
        hasPendingMoment = false
    }

    static func passivePromptAllowed(now: Date = .now) -> Bool {
        guard outcome == nil else { return false }
        guard let last = lastShownDate else { return true }
        let days = defaults.bool(forKey: softDeferKey) ? softDeferCooldownDays : cooldownDays
        return now.timeIntervalSince(last) >= TimeInterval(days) * 86_400
    }

    /// Base eligibility for the enjoyment funnel (passive or from Settings).
    static func canPresentEnjoymentPrompt(hasCompletedSetup: Bool, now: Date = .now) -> Bool {
        guard !ScreenshotConfig.isEnabled else { return false }
        guard hasCompletedSetup else { return false }
        guard passivePromptAllowed(now: now) else { return false }
        guard let first = firstAppOpenDate else { return false }
        return ReviewPromptEligibility(
            targetHitDays: targetHitDays,
            appLaunchCount: appLaunchCount,
            daysSinceFirstOpen: Int(now.timeIntervalSince(first) / 86_400)
        ).isEligible
    }

    /// Passive prompt: eligibility plus a target hit we have not acted on yet.
    static func shouldShowPassively(hasCompletedSetup: Bool, now: Date = .now) -> Bool {
        guard hasPendingMoment else { return false }
        return canPresentEnjoymentPrompt(hasCompletedSetup: hasCompletedSetup, now: now)
    }

    static func markShown(now: Date = .now) {
        lastShownDate = now
        defaults.set(false, forKey: softDeferKey)
        consumePendingMoment()
    }

    /// True after "Maybe later" until the next hard `markShown` / outcome. Hosts
    /// must not call `markShown()` on sheet dismiss when this is true — that
    /// would clear the flag and apply the 120-day jail instead.
    static var isSoftDeferred: Bool {
        defaults.bool(forKey: softDeferKey)
    }

    static func markSoftDeferred(now: Date = .now) {
        lastShownDate = now
        defaults.set(true, forKey: softDeferKey)
        consumePendingMoment()
    }

    static func markOpenedWriteReview() {
        outcome = .openedWriteReview
        markShown()
    }

    static func markFeedbackSubmitted() {
        outcome = .submittedFeedback
        markShown()
    }
}
