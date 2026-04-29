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
        guard let last = lastFeedingEvent else { return false }
        let hours = max(1, UserDefaults.standard.integer(forKey: "overdueThresholdHours"))
        let threshold = hours == 0 ? 12 : hours  // 0 means key not set yet, default to 12
        return Date().timeIntervalSince(last.timestamp) >= Double(threshold) * 3600
    }

    var todaysFeedingCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return (feedingEvents ?? []).filter { $0.timestamp >= startOfDay }.count
    }

    func decrementStock() {
        foodStockCount = max(0, foodStockCount - 1)
    }
}
