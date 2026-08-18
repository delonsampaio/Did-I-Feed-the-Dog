import Foundation

/// Single source of truth for age formatting, shared by the SwiftData `Pet` and the
/// Core Data `SharedPet` so the two model layers can't drift.
func dogAgeString(from birthday: Date?) -> String {
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

/// Read surface the dashboard/PetCard need, conformed by both owned (`Pet`) and
/// shared (`SharedPet`) dogs so they render through one path.
protocol DogDisplayable {
    var id: UUID { get }
    var displayName: String { get }
    var photoData: Data? { get }
    var birthday: Date? { get }
    var isFasting: Bool { get }
    var notificationsMuted: Bool { get }
    var lastFeedingDate: Date? { get }
    var todaysFeedingCount: Int { get }
    var feedingScheduleTimes: [Int] { get }
    var ageString: String { get }
    var isShared: Bool { get }
}

extension Pet: DogDisplayable {
    var displayName: String { name ?? "Dog" }
    var isShared: Bool { false }
    // `id`, `photoData`, `birthday`, `isFasting`, `notificationsMuted`,
    // `lastFeedingDate`, `ageString` already exist on Pet.
    // `todaysFeedingCount` is stored as Int already.
}

extension SharedPet: DogDisplayable {
    var displayName: String { name ?? "Dog" }
    var isShared: Bool { true }
    var ageString: String { dogAgeString(from: birthday) }

    /// Mirrors `Pet.feedingScheduleTimes`: [Int] backed by a comma-joined string.
    var feedingScheduleTimes: [Int] {
        feedingScheduleTimesRaw.split(separator: ",").compactMap { Int($0) }
    }

    /// Derived from feedingEvents rather than a stored counter, so two devices logging
    /// concurrently both count — see SharedFeedingLogService.
    var todaysFeedingCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let events = (feedingEvents as? Set<SharedFeedingEvent>) ?? []
        return events.filter { $0.timestamp >= startOfDay }.count
    }

    /// Derived from feedingEvents rather than a stored field, for the same concurrent-write
    /// reason as todaysFeedingCount. The Core Data model still declares a lastFeedingDate
    /// attribute (harmless, unused by the app — see the Phase 6 spec).
    var lastFeedingDate: Date? {
        let events = (feedingEvents as? Set<SharedFeedingEvent>) ?? []
        return events.map(\.timestamp).max()
    }
}
