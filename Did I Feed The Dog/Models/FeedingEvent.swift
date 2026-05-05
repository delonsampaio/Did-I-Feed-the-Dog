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

    var resolvedMealType: MealType { MealType.from(mealType ?? "") }

    /// True iff we know this event actually decremented stock when it was
    /// logged. Used by undo and "Delete & Restore Portion" to avoid granting
    /// free portions for treats, snacks, or no-deduct custom meals.
    var actuallyDeductedStock: Bool {
        // For events from older app versions (didDeductStock is nil), fall back
        // to the meal-type heuristic — the same logic the legacy code used.
        didDeductStock ?? resolvedMealType.decrementsStock
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
