import AppIntents

enum MealTypeAppEnum: String, AppEnum {
    case morning, evening, breakfast, lunch, dinner, snack

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Meal")
    static var caseDisplayRepresentations: [MealTypeAppEnum: DisplayRepresentation] = [
        .morning:   "Morning",
        .evening:   "Evening",
        .breakfast: "Breakfast",
        .lunch:     "Lunch",
        .dinner:    "Dinner",
        .snack:     "Snack"
    ]

    var label: String {
        switch self {
        case .morning:   return "Morning"
        case .evening:   return "Evening"
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snack:     return "Snack"
        }
    }
}
