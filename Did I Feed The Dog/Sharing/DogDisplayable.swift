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
    var todaysFeedingCount: Int { Int(todaysFeedingCountRaw) }
    var ageString: String { dogAgeString(from: birthday) }
}
