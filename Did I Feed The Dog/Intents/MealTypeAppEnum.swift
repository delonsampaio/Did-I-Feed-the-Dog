import AppIntents
import Foundation

enum MealTypeAppEnum: String, AppEnum {
    case morning, afternoon, evening, breakfast, lunch, dinner, snack, treat

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Meal")
    static var caseDisplayRepresentations: [MealTypeAppEnum: DisplayRepresentation] = [
        .morning:   "Morning",
        .afternoon: "Afternoon",
        .evening:   "Evening",
        .breakfast: "Breakfast",
        .lunch:     "Lunch",
        .dinner:    "Dinner",
        .snack:     "Snack",
        .treat:     "Treat"
    ]

    var label: String {
        switch self {
        case .morning:   return "Morning"
        case .afternoon: return "Afternoon"
        case .evening:   return "Evening"
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snack:     return "Snack"
        case .treat:     return "Treat"
        }
    }

    var deductsStock: Bool {
        switch self {
        case .snack, .treat: return false
        default: return true
        }
    }

    // Used by FeedAllDogsIntent when the user invokes the shortcut without
    // specifying a meal ("Feed all dogs"). Picks a sensible default based on
    // current time so history rows show a real preset (not "Meal" / Custom).
    static func defaultForCurrentTime(_ now: Date = .now) -> MealTypeAppEnum {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 0..<11:  return .breakfast
        case 11..<16: return .lunch
        case 16..<23: return .dinner
        default:      return .snack // late night
        }
    }
}
