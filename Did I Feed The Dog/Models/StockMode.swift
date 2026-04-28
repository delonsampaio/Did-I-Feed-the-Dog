import Foundation

enum StockMode: String, CaseIterable {
    case individual
    case shared
    case none

    var label: String {
        switch self {
        case .individual: return "Per Dog"
        case .shared:     return "Shared Pool"
        case .none:       return "Not Tracked"
        }
    }
}
