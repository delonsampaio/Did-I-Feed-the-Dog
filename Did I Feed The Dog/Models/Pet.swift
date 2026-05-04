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

    var isFeedingOverdue: Bool {
        // Fasting dogs are never marked as overdue
        if isFasting { return false }
        
        let modeRaw = UserDefaults.standard.string(forKey: "reminderMode") ?? ""

        if modeRaw == "allDogs" {
            let raw = UserDefaults.standard.string(forKey: "allDogsReminderTimesRaw") ?? ""
            let times = raw.split(separator: ",").compactMap { Int($0) }.sorted()
            if !times.isEmpty { return isOverdueForSchedule(times) }
        } else if modeRaw == "perDog" {
            let times = feedingScheduleTimes.sorted()
            if !times.isEmpty { return isOverdueForSchedule(times) }
        }

        guard let last = lastFeedingEvent else { return true }
        let hours = max(1, UserDefaults.standard.integer(forKey: "overdueThresholdHours"))
        return Date().timeIntervalSince(last.timestamp) >= Double(hours) * 3600
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