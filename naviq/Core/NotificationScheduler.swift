import Foundation
import UserNotifications

/// Local deadline reminders for tracked applications. Reminders are
/// scheduled on-device only; nothing is pushed from the server.
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()
    private let prefix = "naviq.app."

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Asks for permission. Call only from a user action (e.g. setting a reminder).
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Re-schedules reminders for every active application with a future date.
    func sync(applications: [TrackedApplication], daysBefore: Int, enabled: Bool) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled, await authorizationStatus() == .authorized else { return }

        let now = Date()
        for app in applications where !app.archived {
            if let deadline = app.deadline, app.status.isPreApply {
                let fire = Calendar.current.date(byAdding: .day, value: -daysBefore, to: deadline) ?? deadline
                let when = max(fire, now.addingTimeInterval(60))
                if when < deadline {
                    schedule(id: "\(prefix)\(app.id).deadline", at: when,
                             title: "Deadline approaching",
                             body: "\(app.title) closes \(deadline.formatted(.relative(presentation: .named))).")
                }
            }
            if let due = app.nextActionDue, let action = app.nextAction, due > now {
                let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due
                schedule(id: "\(prefix)\(app.id).action", at: max(morning, now.addingTimeInterval(60)),
                         title: "Next step: \(app.title)", body: action)
            }
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
    }

    private func schedule(id: String, at date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        center.add(request)
    }
}
