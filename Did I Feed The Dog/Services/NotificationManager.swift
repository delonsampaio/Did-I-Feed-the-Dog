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

    func scheduleLowStockNotification(for pet: Pet, stockCount: Int? = nil) {
        guard UIApplication.shared.applicationState != .active else { return }
        let count = stockCount ?? pet.foodStockCount
        let content = UNMutableNotificationContent()
        content.title = "🦴 Time to Restock \(pet.name ?? "your dog")'s Food"
        content.body = "Only \(count) portion\(count == 1 ? "" : "s") remaining."
        content.sound = .default

        let identifier = lowStockIdentifier(for: pet)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleSharedLowStockNotification(stockCount: Int) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "🦴 Time to Restock the Food"
        content.body = "Only \(stockCount) portion\(stockCount == 1 ? "" : "s") remaining in the shared pool."
        content.sound = .default

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["lowstock-shared"])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
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
