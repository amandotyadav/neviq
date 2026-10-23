import Foundation
import UserNotifications

/// Keeps local reminders in sync with the tracker after any change.
enum ReminderCoordinator {
    /// Reads current preferences and applications, then reschedules.
    /// Permission is requested only when the user just performed an action
    /// that benefits from reminders.
    static func syncAfterChange(requestPermission: Bool = false) async {
        guard let user = try? await NaviqAPI.me() else { return }
        let prefs = user.notificationPrefs
        guard prefs.deadlineReminders else {
            await NotificationScheduler.shared.cancelAll()
            return
        }
        if requestPermission, await NotificationScheduler.shared.authorizationStatus() == .notDetermined {
            _ = await NotificationScheduler.shared.requestPermission()
        }
        guard let apps = try? await NaviqAPI.applications() else { return }
        await NotificationScheduler.shared.sync(applications: apps, daysBefore: prefs.reminderDaysBefore, enabled: true)
    }
}
