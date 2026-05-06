import AppIntents
import Foundation

enum MealTypeAppEnum: String, AppEnum {
    case morning, afternoon, evening, breakfast, lunch, dinner, snack, treat

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Meal")
    static var caseDisplayRepresentations: [MealTypeAppEnum: DisplayRepresentation] = [
        .morning:   DisplayRepresentation(title: "Morning", synonyms: ["the morning", "morning meal"]),
        .afternoon: DisplayRepresentation(title: "Afternoon", synonyms: ["the afternoon", "midday"]),
        .evening:   DisplayRepresentation(title: "Evening", synonyms: ["the evening", "night"]),
        .breakfast: DisplayRepresentation(title: "Breakfast", synonyms: ["brekkie"]),
        .lunch:     DisplayRepresentation(title: "Lunch", synonyms: ["a lunch"]),
        .dinner:    DisplayRepresentation(title: "Dinner", synonyms: ["supper", "din din"]),
        .snack:     DisplayRepresentation(title: "Snack", synonyms: ["a snack", "snacks"]),
        .treat:     DisplayRepresentation(title: "Treat", synonyms: ["a treat", "treats", "bone"])
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
