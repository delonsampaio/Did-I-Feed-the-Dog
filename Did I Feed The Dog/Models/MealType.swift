import Foundation

enum MealType: Hashable {
    case morning, evening, breakfast, lunch, afternoon, dinner, snack, treat, custom(String)

    var label: String {
        switch self {
        case .morning:           return "Morning"
        case .evening:           return "Evening"
        case .breakfast:         return "Breakfast"
        case .lunch:             return "Lunch"
        case .afternoon:         return "Afternoon"
        case .dinner:            return "Dinner"
        case .snack:             return "Snack"
        case .treat:             return "Treat"
        case .custom(let text):  return text
        }
    }

    var emoji: String {
        switch self {
        case .morning:    return "🌅"
        case .evening:    return "🌙"
        case .breakfast:  return "🍳"
        case .lunch:      return "🥗"
        case .afternoon:  return "☀️"
        case .dinner:     return "🍽️"
        case .snack:      return "🐾"
        case .treat:      return "🦴"
        case .custom:     return "✏️"
        }
    }

    // Snack and Treat are supplementary — they don't count against the food bag stock
    var decrementsStock: Bool {
        switch self {
        case .snack, .treat: return false
        default:             return true
        }
    }

    /// Default portions deducted when a user hasn't customised this meal type.
    /// Matches the pre-portion-size behaviour (Snack/Treat = 0, all others = 1).
    var defaultPortionSize: Int {
        switch self {
        case .snack, .treat: return 0
        default:             return 1
        }
    }

    static let presets: [MealType] = [.breakfast, .lunch, .dinner, .morning, .afternoon, .evening, .snack, .treat]

    static func emoji(for label: String) -> String {
        presets.first { $0.label == label }?.emoji ?? "✏️"
    }

    static func from(_ stored: String) -> MealType {
        presets.first { $0.label == stored } ?? .custom(stored)
    }
}
