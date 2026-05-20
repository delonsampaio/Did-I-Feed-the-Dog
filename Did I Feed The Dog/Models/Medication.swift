import Foundation
import SwiftData

@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var dose: String = ""
    var frequencyHours: Int = 24
    var notificationsEnabled: Bool = false
    var reminderMinutes: [Int] = [] // empty = relative (fire at lastGiven + freq); non-empty = fixed times of day
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

    // Returns the next one-shot notification date for relative mode only.
    // Returns nil if using fixed-time mode (NotificationManager schedules those directly).
    func nextNotificationDate() -> Date? {
        guard reminderMinutes.isEmpty else { return nil }
        return nextDueDate
    }

    var frequencyLabel: String {
        switch frequencyHours {
        case 8:   return "3 times daily"
        case 12:  return "Twice daily"
        case 24:  return "Daily"
        case 48:  return "Every 2 days"
        case 72:  return "Every 3 days"
        case 168: return "Weekly"
        default:  return "Every \(frequencyHours)h"
        }
    }
}
