import Foundation

enum MealType: Equatable {
    case morning, evening, breakfast, lunch, dinner, snack, custom(String)

    var label: String {
        switch self {
        case .morning:           return "Morning"
        case .evening:           return "Evening"
        case .breakfast:         return "Breakfast"
        case .lunch:             return "Lunch"
        case .dinner:            return "Dinner"
        case .snack:             return "Snack"
        case .custom(let text):  return text
        }
    }

    var emoji: String {
        switch self {
        case .morning:   return "🌅"
        case .evening:   return "🌙"
        case .breakfast: return "🍳"
        case .lunch:     return "🥗"
        case .dinner:    return "🍽️"
        case .snack:     return "🦴"
        case .custom:    return "✏️"
        }
    }

    static let presets: [MealType] = [.morning, .evening, .breakfast, .lunch, .dinner, .snack]
}
