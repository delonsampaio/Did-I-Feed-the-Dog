import CoreData
import Foundation

/// Shared-dog analog of FeedingLogService, deliberately thin: it only creates the
/// SharedFeedingEvent. No stock mutation — SharedPet.effectiveFoodStockCount derives current
/// stock from feedingEvents instead (see the Phase 6 spec) — and none of FeedingLogService's
/// owned-dog-only side effects (low-stock notifications, overdue scheduling, reminder
/// suppression, widget/badge refresh) apply to shared dogs yet.
@MainActor
enum SharedFeedingLogService {

    static func logFeeding(
        for pet: SharedPet,
        mealLabel: String,
        deductsStock: Bool,
        timestamp: Date = .now,
        notes: String = "",
        logger: String,
        in context: NSManagedObjectContext
    ) throws -> SharedFeedingEvent {
        let portionsToDeduct = resolvePortions(mealLabel: mealLabel, deductsStock: deductsStock)

        let event = SharedFeedingEvent(context: context)
        event.timestamp = timestamp
        event.mealType = mealLabel
        event.notes = notes
        event.loggedBy = logger
        event.didDeductStock = NSNumber(value: portionsToDeduct > 0)
        event.portionsDeducted = NSNumber(value: portionsToDeduct)
        event.ckRecordName = UUID().uuidString
        event.pet = pet

        try context.save()
        return event
    }

    /// Mirrors FeedingLogService.resolvePortions verbatim: custom meals use the explicit
    /// toggle (0 or 1); preset meals always look up the user's configured portion size,
    /// regardless of the toggle, so per-meal-type multipliers apply consistently.
    private static func resolvePortions(mealLabel: String, deductsStock: Bool) -> Int {
        let mealType = MealType.from(mealLabel)
        switch mealType {
        case .custom: return deductsStock ? 1 : 0
        default:      return AppSettings.portionSize(for: mealType)
        }
    }
}
