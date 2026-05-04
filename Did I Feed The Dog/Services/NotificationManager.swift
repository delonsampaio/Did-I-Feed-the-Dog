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
        guard UserDefaults.standard.object(forKey: "overduePushEnabled") as? Bool ?? true else { return }

        let hours = UserDefaults.standard.integer(forKey: "overdueThresholdHours")
        let thresholdHours = hours == 0 ? 12 : max(1, hours)
        let triggerDate = lastFedDate.addingTimeInterval(TimeInterval(thresholdHours * 3600))

        guard triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "⚠️ \(pet.name ?? "Your dog") is overdue for a meal"
        content.body = "It's been over \(thresholdHours) hours since their last feeding."
        content.sound = .default

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

    func scheduleLowStockNotification(for pet: Pet, stockCount: Int? = nil) {
        let count = stockCount ?? pet.foodStockCount
        let name = pet.name ?? "your dog"
        let content = UNMutableNotificationContent()
        content.title = "🦴 Time to Restock \(name)'s Food"
        content.body = count == 0
            ? "\(name) is out of food — time to restock!"
            : "Only \(count) portion\(count == 1 ? "" : "s") remaining for \(name)."
        content.sound = .default

        let identifier = lowStockIdentifier(for: pet)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleSharedLowStockNotification(stockCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🦴 Time to Restock the Food"
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
        guard let birthday = pet.birthday else { return }
        let identifier = birthdayIdentifier(for: pet)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let components = Calendar.current.dateComponents([.month, .day], from: birthday)
        let content = UNMutableNotificationContent()
        content.title = "🎂 Happy Birthday \(pet.name ?? "your dog")!"
        content.body = "Give \(pet.name ?? "them") extra love and pets today!"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func removeBirthdayNotification(for pet: Pet) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [birthdayIdentifier(for: pet)]
        )
    }

    // MARK: - App icon badge

    func updateBadgeCount(pets: [Pet]) {
        let enabled = UserDefaults.standard.object(forKey: "badgeEnabled") as? Bool ?? true
        let count = enabled ? pets.filter { $0.isFeedingOverdue }.count : 0
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }

    func clearBadge() {
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }

    // MARK: - Feeding reminders

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
        for (i, minutes) in times.enumerated() {
            scheduleReminder(
                identifier: "feeding-\(pet.id.uuidString)-\(i)",
                title: "Time to Feed \(pet.name ?? "your dog")",
                body: "Don't forget to feed \(pet.name ?? "your dog")!",
                minutesSinceMidnight: minutes
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
            UserDefaults.standard.set(true, forKey: "needsReminderReschedule")
        case .perDog:
            let times = pet.feedingScheduleTimes
            guard let index = times
                .enumerated()
                .filter({ $0.element > currentMinutes })
                .min(by: { $0.element < $1.element })?.offset else { break }
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["feeding-\(pet.id.uuidString)-\(index)"])
            UserDefaults.standard.set(true, forKey: "needsReminderReschedule")
        }
    }

    func rescheduleIfNeeded(reminderMode: ReminderMode, allDogsReminderTimes: [Int], pets: [Pet]) {
        guard UserDefaults.standard.bool(forKey: "needsReminderReschedule") else { return }
        UserDefaults.standard.set(false, forKey: "needsReminderReschedule")
        switch reminderMode {
        case .none:
            break
        case .allDogs:
            scheduleAllDogsReminders(times: allDogsReminderTimes, petNames: pets.map { $0.name ?? "Unknown" })
        case .perDog:
            for pet in pets {
                schedulePerDogReminders(for: pet, times: pet.feedingScheduleTimes)
            }
        }
    }

    func removeAllFeedingReminders(petIds: [UUID]) {
        removeAllDogsReminders()
        for id in petIds {
            let ids = (0..<5).map { "feeding-\(id.uuidString)-\($0)" }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func scheduleReminder(identifier: String, title: String, body: String, minutesSinceMidnight: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        var components = DateComponents()
        components.hour   = minutesSinceMidnight / 60
        components.minute = minutesSinceMidnight % 60

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
