import Foundation
import SwiftData

@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var dose: String = ""
    var frequencyHours: Int = 24
    var notificationsEnabled: Bool = false
    var preferredReminderMinutes: Int? // nil = relative (fire at lastGiven + freq); set = fixed time of day
    var lastGivenDate: Date?

    var pet: Pet?
    @Relationship(deleteRule: .cascade, inverse: \MedicationLog.medication)
    var logs: [MedicationLog]?

    init(name: String, dose: String = "", frequencyHours: Int = 24, notificationsEnabled: Bool = false) {
        self.id = UUID()
        self.name = name
        self.dose = dose
        self.frequencyHours = frequencyHours
        self.notificationsEnabled = notificationsEnabled
        self.lastGivenDate = nil
    }

    var isDue: Bool {
        guard let last = lastGivenDate else { return true }
        return Date() >= last.addingTimeInterval(TimeInterval(frequencyHours * 3600))
    }

    var nextDueDate: Date? {
        lastGivenDate.map { $0.addingTimeInterval(TimeInterval(frequencyHours * 3600)) }
    }

    // Returns when the next push notification should fire.
    // Fixed-time mode: the preferred clock time on (or after) the due date.
    // Relative mode: exactly at nextDueDate (lastGiven + frequencyHours).
    // Returns nil when the trigger would be in the past or can't be determined.
    func nextNotificationDate() -> Date? {
        guard let minutes = preferredReminderMinutes else { return nextDueDate }
        let cal = Calendar.current
        let hour = minutes / 60
        let min = minutes % 60
        // Anchor: the date the dose becomes due (or now when never given)
        let anchor = nextDueDate ?? Date()
        // Find the preferred clock time on the anchor's calendar day
        guard var candidate = cal.date(bySettingHour: hour, minute: min, second: 0, of: anchor) else { return nil }
        // If that time is before the anchor (e.g. dose due at 10pm but reminder is 8am),
        // advance one day so we don't remind before the dose is actually due.
        if candidate < anchor {
            guard let next = cal.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = next
        }
        return candidate > Date() ? candidate : nil
    }

    var frequencyLabel: String {
        switch frequencyHours {
        case 12:  return "Twice daily"
        case 24:  return "Daily"
        case 48:  return "Every 2 days"
        case 72:  return "Every 3 days"
        case 168: return "Weekly"
        default:  return "Every \(frequencyHours)h"
        }
    }
}
