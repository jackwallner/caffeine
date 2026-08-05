import Foundation

/// Gates the one-time "What's New" announcement after an update. Tracks the
/// *announcement content*, not the marketing version, so an unrelated build
/// bump doesn't re-trigger the sheet.
///
/// Fresh installs are seeded past it in `GoalSettings.init` so they get
/// onboarding rather than a "what changed" pitch for an app they have never
/// used.
enum WhatsNew {
    static let currentVersion = "1.0"

    static func shouldShow(lastShown: String?) -> Bool {
        lastShown != currentVersion
    }
}
