import Foundation
import SwiftData

// Shared feeding-log path used by the in-app sheets, AppIntents, quick actions,
// and widget deep links. Everything that creates a FeedingEvent must funnel
// through here so stock decrement, low-stock notifications, overdue scheduling,
// reminder suppression, save, and widget refresh stay in lockstep across
// entry points. Drift between the sheets and intents was the source of
// "Siri-logged meals don't suppress reminders / don't warn on low stock" bugs.
@MainActor
enum FeedingLogService {

    struct LogResult {
        let event: FeedingEvent
        /// True when this log dropped stock to or below the user's low-stock threshold.
        /// Callers (sheets) use this to fire warning haptics; the push notification
        /// itself is already scheduled by the service.
        let didTriggerLowStock: Bool
    }

    struct BatchResult {
        let events: [FeedingEvent]
        /// Per-pet flag for individual mode; true once if shared mode crossed the threshold.
        let didTriggerLowStock: Bool
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
        let event = FeedingEvent(
            timestamp: timestamp,
            mealType: mealLabel,
            notes: notes,
            loggedBy: logger,
            pet: pet
        )
        context.insert(event)

        let triggered = applyStockSideEffects(for: pet, deductsStock: deductsStock)
        NotificationManager.shared.scheduleOverdueNotification(for: pet, lastFedDate: timestamp)
        suppressNextReminder(for: pet)

        try? context.save()
        WidgetDataWriter.write(from: context)

        return LogResult(event: event, didTriggerLowStock: triggered)
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
        let mode = currentStockMode

        for pet in pets {
            let event = FeedingEvent(
                timestamp: timestamp,
                mealType: mealLabel,
                notes: notes,
                loggedBy: logger,
                pet: pet
            )
            context.insert(event)
            created.append(event)

            NotificationManager.shared.scheduleOverdueNotification(for: pet, lastFedDate: timestamp)

            guard deductsStock else { continue }
            switch mode {
            case .individual:
                pet.decrementStock()
                if pet.foodStockCount <= lowStockThreshold {
                    anyIndividualTriggered = true
                    if lowStockPushEnabled {
                        NotificationManager.shared.scheduleLowStockNotification(for: pet)
                    }
                }
            case .shared:
                let next = max(0, currentSharedStock - 1)
                UserDefaults.standard.set(next, forKey: "sharedFoodStock")
                if next <= lowStockThreshold { sharedTriggered = true }
            case .none:
                break
            }
        }

        // One shared-pool low-stock alert per batch — matches FeedAllDogsSheet.
        if deductsStock, mode == .shared, sharedTriggered, lowStockPushEnabled {
            NotificationManager.shared.scheduleSharedLowStockNotification(stockCount: currentSharedStock)
        }

        if let first = pets.first {
            suppressNextReminder(for: first)
        }

        try? context.save()
        WidgetDataWriter.write(from: context)

        return BatchResult(events: created, didTriggerLowStock: sharedTriggered || anyIndividualTriggered)
    }

    // MARK: - Helpers

    @discardableResult
    private static func applyStockSideEffects(for pet: Pet, deductsStock: Bool) -> Bool {
        guard deductsStock else { return false }
        switch currentStockMode {
        case .individual:
            pet.decrementStock()
            let triggered = pet.foodStockCount <= lowStockThreshold
            if triggered, lowStockPushEnabled {
                NotificationManager.shared.scheduleLowStockNotification(for: pet)
            }
            return triggered
        case .shared:
            let next = max(0, currentSharedStock - 1)
            UserDefaults.standard.set(next, forKey: "sharedFoodStock")
            let triggered = next <= lowStockThreshold
            if triggered, lowStockPushEnabled {
                NotificationManager.shared.scheduleSharedLowStockNotification(stockCount: next)
            }
            return triggered
        case .none:
            return false
        }
    }

    private static func suppressNextReminder(for pet: Pet) {
        let modeRaw = UserDefaults.standard.string(forKey: "reminderMode") ?? ""
        guard let mode = ReminderMode(rawValue: modeRaw) else { return }
        let times = (UserDefaults.standard.string(forKey: "allDogsReminderTimesRaw") ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
        NotificationManager.shared.suppressNextUpcomingReminder(
            reminderMode: mode,
            for: pet,
            allDogsReminderTimes: times
        )
    }

    private static var currentStockMode: StockMode {
        StockMode(rawValue: UserDefaults.standard.string(forKey: "stockMode") ?? "") ?? .none
    }

    private static var currentSharedStock: Int {
        UserDefaults.standard.integer(forKey: "sharedFoodStock")
    }

    // Mirrors the @AppStorage default in SettingsView.
    private static var lowStockThreshold: Int {
        let stored = UserDefaults.standard.integer(forKey: "lowStockThreshold")
        return stored == 0 ? 5 : stored
    }

    private static var lowStockPushEnabled: Bool {
        UserDefaults.standard.object(forKey: "lowStockPushEnabled") as? Bool ?? true
    }
}
