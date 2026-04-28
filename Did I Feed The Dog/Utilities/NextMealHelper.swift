import Foundation

func nextMealTime(from minutesSinceMidnight: [Int]) -> Date? {
    guard !minutesSinceMidnight.isEmpty else { return nil }
    let calendar = Calendar.current
    let now = Date()
    let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    let sorted = minutesSinceMidnight.sorted()
    if let next = sorted.first(where: { $0 > currentMinutes }) {
        return calendar.date(bySettingHour: next / 60, minute: next % 60, second: 0, of: now)
    }
    if let first = sorted.first,
       let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
        return calendar.date(bySettingHour: first / 60, minute: first % 60, second: 0, of: tomorrow)
    }
    return nil
}

func nextMealLabel(from minutesSinceMidnight: [Int]) -> (value: String, unit: String)? {
    guard let date = nextMealTime(from: minutesSinceMidnight) else { return nil }
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    let unit = Calendar.current.isDateInToday(date) ? "today" : "tomorrow"
    return (formatter.string(from: date), unit)
}
