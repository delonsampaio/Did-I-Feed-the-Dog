import Foundation

// Centralizes the rules for "what feeding reminders should be active right
// now". Previously this logic was split between SettingsView.updateReminders,
// NotificationManager.rescheduleIfNeeded, and ad-hoc onChange handlers, and
// it skipped the case where a user added/renamed a dog while in All-Dogs mode
// (the body of the daily reminder still listed the old set of names).
@MainActor
enum RemindersCoordinator {

    /// Re-applies the user's reminder settings to UNUserNotificationCenter
    /// based on the current pet roster. Safe to call repeatedly.
    static func refresh(pets: [Pet]) {
        let mode = AppSettings.reminderMode
        let times = AppSettings.allDogsReminderTimes

        switch mode {
        case .none:
            NotificationManager.shared.removeAllFeedingReminders(petIds: pets.map(\.id))

        case .allDogs:
            // Fasting and muted dogs should not be named in the reminder body.
            let activeNames = pets.filter { !$0.isFasting && !$0.notificationsMuted }.compactMap { $0.name }
            // Always remove first so renamed/added/removed dogs are reflected
            // in the notification body the next time it fires.
            NotificationManager.shared.removeAllDogsReminders()
            if !activeNames.isEmpty, !times.isEmpty {
                NotificationManager.shared.scheduleAllDogsReminders(times: times, petNames: activeNames)
            }

        case .perDog:
            NotificationManager.shared.removeAllDogsReminders()
            for pet in pets {
                NotificationManager.shared.schedulePerDogReminders(for: pet, times: pet.feedingScheduleTimes)
            }
        }
    }

    /// Called when a feeding is logged so the next upcoming reminder is
    /// suppressed. Marks the rescheduling flag so the dashboard re-applies
    /// reminders next time it appears.
    static func suppressNext(for pet: Pet) {
        let mode = AppSettings.reminderMode
        guard mode != .none else { return }
        NotificationManager.shared.suppressNextUpcomingReminder(
            reminderMode: mode,
            for: pet,
            allDogsReminderTimes: AppSettings.allDogsReminderTimes
        )
    }
}
