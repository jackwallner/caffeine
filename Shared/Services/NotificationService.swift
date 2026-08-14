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

    /// Whether iOS will actually deliver anything. The toggle in Settings has to
    /// ask, or it sits there switched on in front of a user who denied the
    /// system prompt and will never see a notification.
    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Schedules (or reschedules) the evening nudge from the day's real total.
    ///
    /// Called on every reconcile, not only when the user taps a preset, because
    /// a local notification cannot recompute its own body at fire time: the
    /// number is only as fresh as the last reschedule.
    ///
    /// Hitting the target does not cancel the feature, it only skips today: a
    /// met target reschedules from tomorrow instead of removing the request, so
    /// the reminder does not quietly delete itself on the first good day.
    static func scheduleReminder(hour: Int, total: Double, target: Double, now: Date = .now) async {
        cancelReminder()
        guard target > 0 else { return }
        guard await isAuthorized() else { return }

        let hour = min(max(hour, 0), 23)
        let alreadyMet = ProteinReconciliation.hasMetTarget(total: total, target: target)
        let content = UNMutableNotificationContent()
        content.title = "Protein check-in"
        content.body = alreadyMet
            ? "Log what you have eaten to keep today's total accurate."
            : "\(Int(total.rounded())) g of \(Int(target.rounded())) g tracked today. Log your next protein serving when you have it."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        let trigger: UNNotificationTrigger
        if alreadyMet {
            // The next repeating occurrence is tomorrow whether today's hour
            // has passed or not. Give that future notification fresh-day copy
            // instead of carrying today's finished-day message into tomorrow.
            // The next reconcile restores the repeating request.
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            var dated = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
            dated.hour = hour
            dated.minute = 0
            trigger = UNCalendarNotificationTrigger(dateMatching: dated, repeats: false)
            content.body = "A fresh \(Int(target.rounded())) g today. Log as you go and the wrist keeps the count."
        } else {
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }

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
