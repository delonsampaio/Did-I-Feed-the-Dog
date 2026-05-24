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
    @Relationship(deleteRule: .nullify, inverse: \MedicationLog.medication)
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
        if !reminderMinutes.isEmpty {
            // Multi-day frequencies (every 2 days, weekly, monthly) with a fixed time mean
            // "fire at that time on the due date", not "fire at that time every day".
            // Fall back to relative-mode logic so we don't show due the very next day.
            if frequencyHours > 24 {
                guard let last = lastGivenDate else { return true }
                return Date() >= last.addingTimeInterval(TimeInterval(frequencyHours * 3600))
            }

            // Sub-daily / daily fixed-time mode: due if any scheduled time today or
            // yesterday has passed since the last logged dose.
            let cal = Calendar.current
            let now = Date()
            for dayOffset in [0, -1] {
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                let dayBase = cal.dateComponents([.year, .month, .day], from: day)
                for minutes in reminderMinutes {
                    var comps = dayBase
                    comps.hour = minutes / 60
                    comps.minute = minutes % 60
                    comps.second = 0
                    guard let reminderDate = cal.date(from: comps), reminderDate <= now else { continue }
                    guard let last = lastGivenDate else { return true }
                    if reminderDate > last { return true }
                }
            }
            return false
        }
        // Relative mode: due once frequencyHours have elapsed since the last dose.
        guard let last = lastGivenDate else { return true }
        return Date() >= last.addingTimeInterval(TimeInterval(frequencyHours * 3600))
    }

    var nextDueDate: Date? {
        lastGivenDate.map { $0.addingTimeInterval(TimeInterval(frequencyHours * 3600)) }
    }

    /// The next moment when `isDue` will flip from false to true.
    /// Nil when the medication is already due or has no computable future date.
    var nextDueTransition: Date? {
        guard !isDue else { return nil }
        if reminderMinutes.isEmpty || frequencyHours > 24 {
            return lastGivenDate?.addingTimeInterval(TimeInterval(frequencyHours * 3600))
        }
        // Fixed-time sub-daily/daily: first scheduled slot after lastGivenDate and after now
        let cal = Calendar.current
        let now = Date()
        let base = lastGivenDate ?? .distantPast
        for dayOffset in 0...2 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            var dayBase = cal.dateComponents([.year, .month, .day], from: day)
            for minutes in reminderMinutes.sorted() {
                dayBase.hour = minutes / 60
                dayBase.minute = minutes % 60
                dayBase.second = 0
                guard let slot = cal.date(from: dayBase) else { continue }
                if slot > base && slot > now { return slot }
            }
        }
        return nil
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
        case 720: return "Monthly"
        default:  return "Every \(frequencyHours)h"
        }
    }
}
