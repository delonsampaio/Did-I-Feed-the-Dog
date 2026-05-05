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

    var todaysFeedingCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return (feedingEvents ?? []).filter { $0.timestamp >= startOfDay }.count
    }

    func decrementStock() {
        foodStockCount = max(0, foodStockCount - 1)
    }
}
