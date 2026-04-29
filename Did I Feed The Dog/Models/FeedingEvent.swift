import Foundation
import SwiftData

@Model
final class FeedingEvent {
    var timestamp: Date = Date.now
    var mealType: String?
    var notes: String = ""
    var loggedBy: String?
    var pet: Pet?

    init(timestamp: Date = .now, mealType: String? = nil, notes: String = "", loggedBy: String? = nil, pet: Pet) {
        self.timestamp = timestamp
        self.mealType = mealType
        self.notes = notes
        self.loggedBy = loggedBy
        self.pet = pet
    }
}
