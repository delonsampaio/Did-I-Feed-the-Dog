import Foundation
import OSLog
import SwiftData

// Shared feeding-log path used by the in-app sheets, AppIntents, quick actions,
// and widget deep links. Everything that creates a FeedingEvent must funnel
// through here so stock decrement, low-stock notifications, overdue scheduling,
// reminder suppression, save, and widget refresh stay in lockstep across
// entry points. Drift between the sheets and intents was the source of
// "Siri-logged meals don't suppress reminders / don't warn on low stock" bugs.
@MainActor
enum FeedingLogService {

    private static let logger = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "FeedingLog")

    struct LogResult {
        let event: FeedingEvent
        /// True when this log dropped stock to or below the user's low-stock threshold.
        /// Callers (sheets) use this to fire warning haptics; the push notification
        /// itself is already scheduled by the service.
        let didTriggerLowStock: Bool
        /// True when this feeding tried to deduct from a stock that's now at 0
        /// AND the per-scope feeding-at-zero counter landed on a prompt step
        /// (1, 4, 7, …). Callers use this to surface the restock alert.
        let shouldPromptStockOut: Bool
    }

    struct BatchResult {
        let events: [FeedingEvent]
        /// Per-pet flag for individual mode; true once if shared mode crossed the threshold.
        let didTriggerLowStock: Bool
        /// True when at least one zero-stock counter (shared or individual)
        /// landed on a prompt step in this batch.
        let shouldPromptStockOut: Bool
        /// Pets in this batch whose individual stock is at 0 after deduction.
        /// Empty in shared mode — the shared pool is implied by the scope.
        let petsAtZeroStock: [Pet]
    }

    static func logFeeding(
        for pet: Pet,
        mealLabel: String,
        deductsStock: Bool,
        timestamp: Date = .now,
        notes: String = "",
        logger: String,
        in context: ModelContext
    ) -> LogResult {
        let didDeduct = deductsStock && AppSettings.stockMode != .none

        let event = FeedingEvent(
            timestamp: timestamp,
            mealType: mealLabel,
            notes: notes,
            loggedBy: logger,
            pet: pet,
            didDeductStock: didDeduct
        )
        context.insert(event)

        let triggered = applyStockSideEffects(for: pet, deductsStock: deductsStock)
        let shouldPromptStockOut = recordZeroStockIfNeeded(pet: pet, didDeduct: didDeduct)
        NotificationManager.shared.scheduleOverdueNotification(for: pet, lastFedDate: timestamp)
        suppressNextReminder(for: pet)

        save(context)
        WidgetDataWriter.write(from: context)
        refreshBadge(in: context)

        return LogResult(event: event, didTriggerLowStock: triggered, shouldPromptStockOut: shouldPromptStockOut)
    }

    static func logFeedingForAll(
        pets: [Pet],
        mealLabel: String,
        deductsStock: Bool,
        timestamp: Date = .now,
        notes: String = "",
        logger: String,
        in context: ModelContext
    ) -> BatchResult {
        var created: [FeedingEvent] = []
        var sharedTriggered = false
        var anyIndividualTriggered = false
        var petsAtZeroStock: [Pet] = []
        let mode = AppSettings.stockMode
        let didDeduct = deductsStock && mode != .none

        for pet in pets {
            let event = FeedingEvent(
                timestamp: timestamp,
                mealType: mealLabel,
                notes: notes,
                loggedBy: logger,
                pet: pet,
                didDeductStock: didDeduct
            )
            context.insert(event)
            created.append(event)

            NotificationManager.shared.scheduleOverdueNotification(for: pet, lastFedDate: timestamp)

            guard deductsStock else { continue }
            switch mode {
            case .individual:
                pet.decrementStock()
                if pet.foodStockCount <= AppSettings.lowStockThreshold {
                    anyIndividualTriggered = true
                    if AppSettings.lowStockPushEnabled {
                        NotificationManager.shared.scheduleLowStockNotification(for: pet)
                    }
                }
                if pet.foodStockCount == 0 { petsAtZeroStock.append(pet) }
            case .shared:
                let next = max(0, AppSettings.sharedFoodStock - 1)
                AppSettings.sharedFoodStock = next
                if next <= AppSettings.lowStockThreshold { sharedTriggered = true }
            case .none:
                break
            }
        }

        // One shared-pool low-stock alert per batch — matches FeedAllDogsSheet.
        if deductsStock, mode == .shared, sharedTriggered, AppSettings.lowStockPushEnabled {
            NotificationManager.shared.scheduleSharedLowStockNotification(stockCount: AppSettings.sharedFoodStock)
        }

        // Stock-out prompt cadence — increment once per affected scope.
        var shouldPromptStockOut = false
        if didDeduct {
            switch mode {
            case .shared:
                if AppSettings.sharedFoodStock == 0 {
                    shouldPromptStockOut = AppSettings.recordFeedingAtZeroStock(petId: nil)
                }
            case .individual:
                for pet in petsAtZeroStock {
                    let triggered = AppSettings.recordFeedingAtZeroStock(petId: pet.id)
                    shouldPromptStockOut = shouldPromptStockOut || triggered
                }
            case .none:
                break
            }
        }

        if let first = pets.first {
            suppressNextReminder(for: first)
        }

        save(context)
        WidgetDataWriter.write(from: context)
        refreshBadge(in: context)

        return BatchResult(
            events: created,
            didTriggerLowStock: sharedTriggered || anyIndividualTriggered,
            shouldPromptStockOut: shouldPromptStockOut,
            petsAtZeroStock: mode == .individual ? petsAtZeroStock : []
        )
    }

    // MARK: - Helpers

    private static func recordZeroStockIfNeeded(pet: Pet, didDeduct: Bool) -> Bool {
        guard didDeduct else { return false }
        switch AppSettings.stockMode {
        case .individual:
            guard pet.foodStockCount == 0 else { return false }
            return AppSettings.recordFeedingAtZeroStock(petId: pet.id)
        case .shared:
            guard AppSettings.sharedFoodStock == 0 else { return false }
            return AppSettings.recordFeedingAtZeroStock(petId: nil)
        case .none:
            return false
        }
    }

    @discardableResult
    private static func applyStockSideEffects(for pet: Pet, deductsStock: Bool) -> Bool {
        guard deductsStock else { return false }
        switch AppSettings.stockMode {
        case .individual:
            pet.decrementStock()
            let triggered = pet.foodStockCount <= AppSettings.lowStockThreshold
            if triggered, AppSettings.lowStockPushEnabled {
                NotificationManager.shared.scheduleLowStockNotification(for: pet)
            }
            return triggered
        case .shared:
            let next = max(0, AppSettings.sharedFoodStock - 1)
            AppSettings.sharedFoodStock = next
            let triggered = next <= AppSettings.lowStockThreshold
            if triggered, AppSettings.lowStockPushEnabled {
                NotificationManager.shared.scheduleSharedLowStockNotification(stockCount: next)
            }
            return triggered
        case .none:
            return false
        }
    }

    private static func suppressNextReminder(for pet: Pet) {
        let mode = AppSettings.reminderMode
        guard mode != .none else { return }
        NotificationManager.shared.suppressNextUpcomingReminder(
            reminderMode: mode,
            for: pet,
            allDogsReminderTimes: AppSettings.allDogsReminderTimes
        )
    }

    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            logger.error("Failed to save context after feeding log: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func refreshBadge(in context: ModelContext) {
        let pets = (try? context.fetch(FetchDescriptor<Pet>())) ?? []
        NotificationManager.shared.updateBadgeCount(pets: pets)
    }
}
