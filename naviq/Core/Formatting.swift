import Foundation
import UIKit

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}

enum Dates {
    static func daysUntil(_ date: Date, from now: Date = .now) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    }

    /// "Closes in 8 days", "Closes today", "Closed 3 days ago".
    static func deadlinePhrase(_ date: Date?, closedVerb: String = "Closed") -> String {
        guard let date else { return "Deadline not published" }
        let d = daysUntil(date)
        switch d {
        case ..<0: return "\(closedVerb) \(-d) day\(d == -1 ? "" : "s") ago"
        case 0: return "Closes today"
        case 1: return "Closes tomorrow"
        default: return "Closes in \(d) days"
        }
    }

    static func short(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated).year()) }
    static func dayMonth(_ date: Date) -> (day: String, month: String) {
        (date.formatted(.dateTime.day()), date.formatted(.dateTime.month(.abbreviated)).uppercased())
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { trimmed.isEmpty ? nil : trimmed }
}
