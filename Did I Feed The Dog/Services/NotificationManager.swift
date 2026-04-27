import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() async {
        try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge, .provisional]
        )
    }

    func lowStockIdentifier(for pet: Pet) -> String {
        "lowstock-\(pet.id.uuidString)"
    }

    func birthdayIdentifier(for pet: Pet) -> String {
        "birthday-\(pet.id.uuidString)"
    }

    func scheduleLowStockNotification(for pet: Pet) {
        let content = UNMutableNotificationContent()
        content.title = "🦴 Time to Restock \(pet.name)'s Food"
        content.body = "Only \(pet.foodStockCount) portion\(pet.foodStockCount == 1 ? "" : "s") remaining."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: lowStockIdentifier(for: pet),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleBirthdayNotification(for pet: Pet) {
        let identifier = birthdayIdentifier(for: pet)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let components = Calendar.current.dateComponents([.month, .day], from: pet.birthday)
        let content = UNMutableNotificationContent()
        content.title = "🎂 Happy Birthday \(pet.name)!"
        content.body = "Give \(pet.name) extra love and pets today!"
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
}
