import Foundation
import SwiftData

@Model
final class FeedingEvent {
    var timestamp: Date
    var mealType: String
    var notes: String
    var pet: Pet?

    init(timestamp: Date = .now, mealType: String, notes: String = "", pet: Pet) {
        self.timestamp = timestamp
        self.mealType = mealType
        self.notes = notes
        self.pet = pet
    }
}
