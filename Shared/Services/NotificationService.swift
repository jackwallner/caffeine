import Foundation
import os
import UserNotifications

private let notificationLogger = Logger(subsystem: "com.jackwallner.protein", category: "Notifications")

/// One opt-in notification: an evening nudge when the day's target is still
/// short.
///
/// The body is rebuilt from the current total every time the app refreshes, so
/// "You're 42 g short" is a real number rather than a generic reminder. A local
/// notification cannot recompute itself at fire time, so rescheduling on
/// refresh is what keeps it honest.
@MainActor
enum NotificationService {
    static let reminderIdentifier = "protein.daily.reminder"

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            notificationLogger.error("Notification authorization failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Schedules (or reschedules) tonight's nudge. Cancels instead when the
    /// target is already met — nobody needs telling they finished.
    static func scheduleReminder(hour: Int, total: Double, target: Double) async {
        cancelReminder()
        guard target > 0 else { return }
        guard !ProteinReconciliation.hasMetTarget(total: total, target: target) else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let remaining = ProteinReconciliation.remaining(total: total, target: target)
        let content = UNMutableNotificationContent()
        content.title = "Protein check-in"
        content.body = remaining > 0
            ? "\(Int(remaining.rounded())) g to go today. A shake or a tin of tuna closes most of that."
            : "Log what you have eaten to keep today's total accurate."
        content.sound = .default

        var components = DateComponents()
        components.hour = min(max(hour, 0), 23)
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            notificationLogger.error("Reminder scheduling failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }
}
