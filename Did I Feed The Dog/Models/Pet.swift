import Foundation
import SwiftData

@Model
final class Pet {
    var id: UUID
    var name: String
    var birthday: Date
    var photoData: Data?
    var foodStockCount: Int
    @Relationship(deleteRule: .cascade) var feedingEvents: [FeedingEvent] = []

    init(name: String, birthday: Date, photoData: Data? = nil, foodStockCount: Int = 0) {
        self.id = UUID()
        self.name = name
        self.birthday = birthday
        self.photoData = photoData
        self.foodStockCount = foodStockCount
    }

    var ageString: String {
        let components = Calendar.current.dateComponents([.year, .month], from: birthday, to: .now)
        let years = components.year ?? 0
        let months = components.month ?? 0
        switch (years, months) {
        case (0, _):  return "\(months) month\(months == 1 ? "" : "s")"
        case (_, 0):  return "\(years) year\(years == 1 ? "" : "s")"
        default:      return "\(years) year\(years == 1 ? "" : "s"), \(months) month\(months == 1 ? "" : "s")"
        }
    }

    var lastFeedingEvent: FeedingEvent? {
        feedingEvents.max(by: { $0.timestamp < $1.timestamp })
    }

    var isFeedingOverdue: Bool {
        guard let last = lastFeedingEvent else { return true }
        return Date().timeIntervalSince(last.timestamp) >= 12 * 3600
    }

    var todaysFeedingCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return feedingEvents.filter { $0.timestamp >= startOfDay }.count
    }

    func decrementStock() {
        foodStockCount = max(0, foodStockCount - 1)
    }
}
