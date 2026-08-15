import Foundation
import UIKit
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )
    }

    func lowStockIdentifier(for pet: Pet) -> String {
        "lowstock-\(pet.id.uuidString)"
    }

    func birthdayIdentifier(for pet: Pet) -> String {
        "birthday-\(pet.id.uuidString)"
    }

    func overdueIdentifier(for pet: Pet) -> String {
        "overdue-\(pet.id.uuidString)"
    }

    func scheduleOverdueNotification(for pet: Pet, lastFedDate: Date) {
        let identifier = overdueIdentifier(for: pet)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        guard EntitlementManager.shared.isPro else { return }
        guard !pet.isFasting else { return }
        guard !pet.notificationsMuted else { return }
        guard AppSettings.overduePushEnabled else { return }

        let thresholdHours = AppSettings.overdueThresholdHours
        let triggerDate = lastFedDate.addingTimeInterval(TimeInterval(thresholdHours * 3600))

        guard triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "⚠️ \(pet.name ?? "Your dog") is overdue for a meal"
        content.body = "It's been over \(thresholdHours) hours since their last feeding."
        content.sound = .default
        content.threadIdentifier = "dog-\(pet.id.uuidString)"

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func removeOverdueNotification(for pet: Pet) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [overdueIdentifier(for: pet)]
        )
    }

    /// Reschedules (or cancels) the overdue notification based on the pet's
    /// current lastFeedingDate. Call after deleting or undoing a feeding so
    /// the notification anchors to the actual last-fed time rather than the
    /// deleted one.
    func rescheduleOverdueNotification(for pet: Pet) {
        guard let lastDate = pet.lastFeedingDate else {
            removeOverdueNotification(for: pet)
            return
        }
        scheduleOverdueNotification(for: pet, lastFedDate: lastDate)
    }

    func scheduleLowStockNotification(for pet: Pet, stockCount: Int? = nil) {
        let identifier = lowStockIdentifier(for: pet)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        guard EntitlementManager.shared.isPro else { return }
        guard !pet.notificationsMuted else { return }
        let count = stockCount ?? pet.foodStockCount
        let name = pet.name ?? "your dog"
        let content = UNMutableNotificationContent()
        content.title = "🦴 Low Food: \(name)"
        content.body = count == 0
            ? "\(name) is out of food — time to restock!"
            : "Only \(count) portion\(count == 1 ? "" : "s") remaining for \(name)."
        content.sound = .default
        content.threadIdentifier = "dog-\(pet.id.uuidString)"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleSharedLowStockNotification(stockCount: Int) {
        guard EntitlementManager.shared.isPro else { return }
        let content = UNMutableNotificationContent()
        content.title = "🦴 Low Food: Shared"
        content.body = stockCount == 0
            ? "You're out of food — time to restock!"
            : "Only \(stockCount) portion\(stockCount == 1 ? "" : "s") of food remaining."
        content.sound = .default

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["lowstock-shared"])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false)
        let request = UNNotificationRequest(identifier: "lowstock-shared", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleBirthdayNotification(for pet: Pet) {
        guard EntitlementManager.shared.isPro else { return }
        guard let birthday = pet.birthday else { return }
        let identifier = birthdayIdentifier(for: pet)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        guard !pet.notificationsMuted else { return }

        let components = Calendar.current.dateComponents([.month, .day], from: birthday)
        let content = UNMutableNotificationContent()
        content.title = "🎂 Happy Birthday \(pet.name ?? "your dog")!"
        content.body = "Give \(pet.name ?? "them") extra love and pets today!"
        content.sound = .default
        content.threadIdentifier = "dog-\(pet.id.uuidString)"

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func removeBirthdayNotification(for pet: Pet) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [birthdayIdentifier(for: pet)]
        )
    }

    func updateBadgeCount(pets: [Pet]) {
        guard EntitlementManager.shared.isPro else {
            Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
            return
        }
        guard AppSettings.badgeEnabled else {
            Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
            return
        }
        let ctx = OverdueContext.current
        let count = pets.filter { $0.isFeedingOverdue(using: ctx) && !$0.notificationsMuted }.count
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }

    func clearBadge() {
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }

    func scheduleAllDogsReminders(times: [Int], petNames: [String]) {
        removeAllDogsReminders()
        let nameList = ListFormatter.localizedString(byJoining: petNames)
        for (i, minutes) in times.enumerated() {
            scheduleReminder(
                identifier: "feeding-all-\(i)",
                title: "Time to Feed Your Dogs",
                body: "Don't forget to feed \(nameList)!",
                minutesSinceMidnight: minutes
            )
        }
    }

    func schedulePerDogReminders(for pet: Pet, times: [Int]) {
        removePerDogReminders(for: pet)
        guard EntitlementManager.shared.isPro else { return }
        guard !pet.isFasting else { return }
        guard !pet.notificationsMuted else { return }
        
        for (i, minutes) in times.enumerated() {
            scheduleReminder(
                identifier: "feeding-\(pet.id.uuidString)-\(i)",
                title: "Time to Feed \(pet.name ?? "your dog")",
                body: "Don't forget to feed \(pet.name ?? "your dog")!",
                minutesSinceMidnight: minutes,
                threadIdentifier: "dog-\(pet.id.uuidString)"
            )
        }
    }

    func removeAllDogsReminders() {
        let ids = (0..<5).map { "feeding-all-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removePerDogReminders(for pet: Pet) {
        let ids = (0..<5).map { "feeding-\(pet.id.uuidString)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Removes every notification associated with a pet — used both when a pet is deleted
    /// outright and when it's migrated into the shared store (Phase 5 sharing), so no
    /// orphaned repeating notification remains for a pet that's gone from the owned store.
    func removeAllNotifications(for pet: Pet) {
        removeBirthdayNotification(for: pet)
        removeOverdueNotification(for: pet)
        removePerDogReminders(for: pet)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [lowStockIdentifier(for: pet)]
        )
    }

    func suppressNextUpcomingReminder(reminderMode: ReminderMode, for pet: Pet, allDogsReminderTimes: [Int]) {
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)

        switch reminderMode {
        case .none:
            break
        case .allDogs:
            guard let index = allDogsReminderTimes
                .enumerated()
                .filter({ $0.element > currentMinutes })
                .min(by: { $0.element < $1.element })?.offset else { break }
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["feeding-all-\(index)"])
            AppSettings.needsReminderReschedule = true
        case .perDog:
            let times = pet.feedingScheduleTimes
            guard let index = times
                .enumerated()
                .filter({ $0.element > currentMinutes })
                .min(by: { $0.element < $1.element })?.offset else { break }
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["feeding-\(pet.id.uuidString)-\(index)"])
            AppSettings.needsReminderReschedule = true
        }
    }

    func rescheduleIfNeeded(reminderMode: ReminderMode, allDogsReminderTimes: [Int], pets: [Pet]) {
        guard AppSettings.needsReminderReschedule else { return }
        AppSettings.needsReminderReschedule = false
        switch reminderMode {
        case .none:
            break
        case .allDogs:
            // Refinement: Filter out fasting dogs from global reminders
            let activePetNames = pets.filter { !$0.isFasting }.compactMap { $0.name }
            if activePetNames.isEmpty {
                removeAllDogsReminders()
            } else {
                scheduleAllDogsReminders(times: allDogsReminderTimes, petNames: activePetNames)
            }
        case .perDog:
            for pet in pets {
                schedulePerDogReminders(for: pet, times: pet.feedingScheduleTimes)
            }
        }
    }

    func medicationIdentifier(for medication: Medication) -> String {
        "medication-\(medication.id.uuidString)"
    }

    func scheduleMedicationReminder(for medication: Medication, petName: String) {
        removeMedicationReminder(for: medication)
        guard EntitlementManager.shared.isPro else { return }
        guard medication.notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "💊 Medication Due: \(medication.name)"
        content.body = medication.dose.isEmpty
            ? "\(petName) is due for \(medication.name)."
            : "\(petName) is due for \(medication.name) (\(medication.dose))."
        content.sound = .default
        if let petId = medication.pet?.id {
            content.threadIdentifier = "dog-\(petId.uuidString)"
        }

        let base = medicationIdentifier(for: medication)

        if medication.reminderMinutes.isEmpty {
            // Relative mode: one-shot notification at lastGiven + frequencyHours
            guard let triggerDate = medication.nextNotificationDate() else { return }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: base, content: content, trigger: trigger))
        } else {
            // Fixed-time mode: one repeating daily notification per configured time
            for (index, minutes) in medication.reminderMinutes.enumerated() {
                var components = DateComponents()
                components.hour = minutes / 60
                components.minute = minutes % 60
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(base)-\(index)", content: content, trigger: trigger))
            }
        }
    }

    func removeMedicationReminder(for medication: Medication) {
        let base = medicationIdentifier(for: medication)
        let ids = [base] + (0..<3).map { "\(base)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removeAllMedicationReminders(for pet: Pet) {
        let ids = (pet.medications ?? []).flatMap { med -> [String] in
            let base = medicationIdentifier(for: med)
            return [base] + (0..<3).map { "\(base)-\($0)" }
        }
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removeAllAlerts(for pet: Pet) {
        removeOverdueNotification(for: pet)
        removePerDogReminders(for: pet)
        removeAllMedicationReminders(for: pet)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [lowStockIdentifier(for: pet), birthdayIdentifier(for: pet)]
        )
    }

    func removeAllFeedingReminders(petIds: [UUID]) {
        removeAllDogsReminders()
        for id in petIds {
            let ids = (0..<5).map { "feeding-\(id.uuidString)-\($0)" }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func scheduleWaterBowlReminder(weekday: Int, timeMinutes: Int) {
        removeWaterBowlReminder()
        guard EntitlementManager.shared.isPro else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Time to scrub the water bowl! 🧼"
        content.body = "Give it a quick scrub to prevent unhealthy biofilm buildup."
        content.sound = .default
        
        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        dateComponents.hour = timeMinutes / 60
        dateComponents.minute = timeMinutes % 60
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "waterBowlReminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }

    func removeWaterBowlReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["waterBowlReminder"])
    }

    func removeAllProNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { id in
                id.hasPrefix("overdue-") ||
                id.hasPrefix("lowstock-") ||
                id.hasPrefix("birthday-") ||
                id.hasPrefix("medication-") ||
                (id.hasPrefix("feeding-") && !id.hasPrefix("feeding-all-")) ||
                id == "waterBowlReminder"
            }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        clearBadge()
    }

    private func scheduleReminder(identifier: String, title: String, body: String, minutesSinceMidnight: Int, threadIdentifier: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        if let thread = threadIdentifier { content.threadIdentifier = thread }

        var components = DateComponents()
        components.hour   = minutesSinceMidnight / 60
        components.minute = minutesSinceMidnight % 60

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}