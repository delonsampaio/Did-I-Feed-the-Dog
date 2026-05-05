import Foundation
import SwiftData

@Model
final class Pet {
    var id: UUID = UUID()
    var name: String?
    var birthday: Date?
    var photoData: Data?
    var foodStockCount: Int = 0
    var feedingScheduleTimesRaw: String = ""
    var isFasting: Bool = false // Feature #22
    
    @Relationship(deleteRule: .cascade, inverse: \FeedingEvent.pet) var feedingEvents: [FeedingEvent]?

    var feedingScheduleTimes: [Int] {
        get { feedingScheduleTimesRaw.split(separator: ",").compactMap { Int($0) } }
        set { feedingScheduleTimesRaw = newValue.map(String.init).joined(separator: ",") }
    }

    init(name: String? = nil, birthday: Date? = nil, photoData: Data? = nil, foodStockCount: Int = 0, isFasting: Bool = false) {
        self.id = UUID()
        self.name = name
        self.birthday = birthday
        self.photoData = photoData
        self.foodStockCount = foodStockCount
        self.feedingScheduleTimesRaw = ""
        self.isFasting = isFasting
    }

    var ageString: String {
        guard let birthday else { return "" }
        let components = Calendar.current.dateComponents([.year, .month], from: birthday, to: .now)
        let years = components.year ?? 0
        let months = components.month ?? 0
        switch (years, months) {
        case (0, _):  return "Puppy"
        case (_, 0):  return "\(years) year\(years == 1 ? "" : "s")"
        default:      return "\(years) year\(years == 1 ? "" : "s"), \(months) month\(months == 1 ? "" : "s")"
        }
    }

    var lastFeedingEvent: FeedingEvent? {
        (feedingEvents ?? []).max(by: { $0.timestamp < $1.timestamp })
    }

    /// Returns the most recent feedings, newest first. Used by the card's
    /// 3-row mini history. Pulls from the cached relationship so no fetch
    /// hits the store; the cost is a single sort over the pet's events.
    func recentFeedings(limit: Int) -> [FeedingEvent] {
        let events = feedingEvents ?? []
        guard events.count > limit else {
            return events.sorted { $0.timestamp > $1.timestamp }
        }
        return Array(events.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

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

    var todaysFeedingCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return (feedingEvents ?? []).filter { $0.timestamp >= startOfDay }.count
    }

    func decrementStock() {
        foodStockCount = max(0, foodStockCount - 1)
    }
}

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