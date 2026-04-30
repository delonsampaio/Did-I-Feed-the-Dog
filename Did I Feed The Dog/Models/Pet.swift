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
    @Relationship(deleteRule: .cascade) var feedingEvents: [FeedingEvent]?

    var feedingScheduleTimes: [Int] {
        get { feedingScheduleTimesRaw.split(separator: ",").compactMap { Int($0) } }
        set { feedingScheduleTimesRaw = newValue.map(String.init).joined(separator: ",") }
    }

    init(name: String? = nil, birthday: Date? = nil, photoData: Data? = nil, foodStockCount: Int = 0) {
        self.id = UUID()
        self.name = name
        self.birthday = birthday
        self.photoData = photoData
        self.foodStockCount = foodStockCount
        self.feedingScheduleTimesRaw = ""
    }

    var ageString: String {
        guard let birthday else { return "Age unknown" }
        let components = Calendar.current.dateComponents([.year, .month], from: birthday, to: .now)
        let years = components.year ?? 0
        let months = components.month ?? 0
        switch (years, months) {
        case (0, 0):  return "Less than a month"
        case (0, _):  return "\(months) month\(months == 1 ? "" : "s")"
        case (_, 0):  return "\(years) year\(years == 1 ? "" : "s")"
        default:      return "\(years) year\(years == 1 ? "" : "s"), \(months) month\(months == 1 ? "" : "s")"
        }
    }

    var lastFeedingEvent: FeedingEvent? {
        (feedingEvents ?? []).max(by: { $0.timestamp < $1.timestamp })
    }

    var isFeedingOverdue: Bool {
        let modeRaw = UserDefaults.standard.string(forKey: "reminderMode") ?? ""
        let mode = ReminderMode(rawValue: modeRaw) ?? .none

        if mode == .allDogs {
            let raw = UserDefaults.standard.string(forKey: "allDogsReminderTimesRaw") ?? ""
            let times = raw.split(separator: ",").compactMap { Int($0) }.sorted()
            if !times.isEmpty { return isOverdueForSchedule(times) }
        } else if mode == .perDog {
            let times = feedingScheduleTimes.sorted()
            if !times.isEmpty { return isOverdueForSchedule(times) }
        }

        // Fallback: hours-based threshold
        guard let last = lastFeedingEvent else { return false }
        let hours = max(1, UserDefaults.standard.integer(forKey: "overdueThresholdHours"))
        return Date().timeIntervalSince(last.timestamp) >= Double(hours) * 3600
    }

    private func isOverdueForSchedule(_ times: [Int]) -> Bool {
        let cal = Calendar.current
        let now = cal.dateComponents([.hour, .minute], from: .now)
        let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)

        guard let lastPassedMinutes = times.filter({ $0 <= currentMinutes }).last else {
            return false // No scheduled time has passed yet today
        }

        var components = cal.dateComponents([.year, .month, .day], from: .now)
        components.hour = lastPassedMinutes / 60
        components.minute = lastPassedMinutes % 60
        components.second = 0
        guard let scheduledDate = cal.date(from: components) else { return false }

        guard let last = lastFeedingEvent else { return true } // Never fed and a meal time has passed
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
