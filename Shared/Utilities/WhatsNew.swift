import Foundation

/// Gates the one-time "What's New" announcement after an update. Tracks the
/// *announcement content*, not the marketing version, so an unrelated build
/// bump doesn't re-trigger the sheet.
///
/// Fresh installs are seeded past it in `GoalSettings.init` so they get
/// onboarding rather than a "what changed" pitch for an app they have never
/// used.
enum WhatsNew {
    /// Bumped for the 2026-08-10 change of what is paid for: logging went free
    /// on both devices and Protein+ became the month behind the number. Anyone
    /// who installed under the old split has to be told, in the app, once.
    static let currentVersion = "1.1"

    static func shouldShow(lastShown: String?) -> Bool {
        lastShown != currentVersion
    }
}
