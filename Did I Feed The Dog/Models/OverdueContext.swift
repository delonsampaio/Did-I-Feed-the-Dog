import Foundation

/// Snapshot of settings needed to compute `isFeedingOverdue`. Building the
/// snapshot once per render and passing it to N pets avoids re-reading
/// UserDefaults inside the SwiftData property accessor on every redraw.
struct OverdueContext {
    let reminderMode: ReminderMode
    let allDogsReminderTimes: [Int]
    let overdueThresholdHours: Int

    static var current: OverdueContext {
        OverdueContext(
            reminderMode: AppSettings.reminderMode,
            allDogsReminderTimes: AppSettings.allDogsReminderTimes,
            overdueThresholdHours: AppSettings.overdueThresholdHours
        )
    }
}

// Lives outside Pet.swift so the @Model macro doesn't pull these
// main-app-only types into the widget extension target's compilation
// of Pet.swift.
extension Pet {
    var isFeedingOverdue: Bool {
        isFeedingOverdue(using: .current)
    }

    func isFeedingOverdue(using ctx: OverdueContext) -> Bool {
        // Fasting dogs are never marked as overdue.
        if isFasting { return false }

        switch ctx.reminderMode {
        case .allDogs:
            let times = ctx.allDogsReminderTimes.sorted()
            if !times.isEmpty { return isOverdueForSchedule(times) }
        case .perDog:
            let times = feedingScheduleTimes.sorted()
            if !times.isEmpty { return isOverdueForSchedule(times) }
        case .none:
            break
        }

        guard let last = lastFeedingEvent else { return true }
        return Date().timeIntervalSince(last.timestamp) >= Double(ctx.overdueThresholdHours) * 3600
    }

    private func isOverdueForSchedule(_ times: [Int]) -> Bool {
        let cal = Calendar.current
        let now = cal.dateComponents([.hour, .minute], from: .now)
        let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)

        guard let lastPassedMinutes = times.filter({ $0 <= currentMinutes }).last else {
            return false
        }

        var components = cal.dateComponents([.year, .month, .day], from: .now)
        components.hour = lastPassedMinutes / 60
        components.minute = lastPassedMinutes % 60
        components.second = 0
        guard let scheduledDate = cal.date(from: components) else { return false }

        guard let last = lastFeedingEvent else { return true }
        return last.timestamp < scheduledDate
    }
}
