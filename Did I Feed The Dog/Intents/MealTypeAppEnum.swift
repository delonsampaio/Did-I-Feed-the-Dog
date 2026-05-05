import AppIntents

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
}
