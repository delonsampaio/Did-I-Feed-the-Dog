import Foundation
import SwiftData

@Model
final class FeedingEvent {
    var timestamp: Date = Date.now
    var mealType: String?
    var notes: String = ""
    var loggedBy: String?
    var pet: Pet?

    // Records whether this specific event reduced stock at log time. The
    // resolved meal type alone isn't enough — a custom meal might be logged
    // with the "Deduct a portion" toggle off, and stock-tracking mode may have
    // been .none. Without this field, "Delete & Restore Portion" and undo
    // would credit a portion the user never spent. Optional for back-compat
    // with events created before the field existed; nil is treated as "infer
    // from meal type" by callers.
    var didDeductStock: Bool?
    /// Portions actually removed from stock when this event was logged.
    /// Nil on events created before portion-size support — callers fall back
    /// to the legacy bool + meal-type heuristic via deductedPortionCount.
    var portionsDeducted: Int?

    var resolvedMealType: MealType { MealType.from(mealType ?? "") }

    var actuallyDeductedStock: Bool { deductedPortionCount > 0 }

    /// How many stock portions this event removed. Used by all restore paths
    /// (undo, delete & restore, bulk delete & restore).
    var deductedPortionCount: Int {
        if let p = portionsDeducted { return p }
        // Legacy events: stored as a bool; treat as 0 or 1 portion.
        return (didDeductStock ?? resolvedMealType.decrementsStock) ? 1 : 0
    }

    init(
        timestamp: Date = .now,
        mealType: String? = nil,
        notes: String = "",
        loggedBy: String? = nil,
        pet: Pet,
        didDeductStock: Bool? = nil
    ) {
        self.timestamp = timestamp
        self.mealType = mealType
        self.notes = notes
        self.loggedBy = loggedBy
        self.pet = pet
        self.didDeductStock = didDeductStock
    }
}
