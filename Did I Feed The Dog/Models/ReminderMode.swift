import Foundation

enum ReminderMode: String, CaseIterable {
    case none    = "none"
    case allDogs = "allDogs"
    case perDog  = "perDog"

    var label: String {
        switch self {
        case .none:    return "Off"
        case .allDogs: return "All Dogs"
        case .perDog:  return "Per Dog"
        }
    }
}
