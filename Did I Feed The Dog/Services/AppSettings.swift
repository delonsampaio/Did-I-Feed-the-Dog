import Foundation

// Centralized facade over UserDefaults / @AppStorage keys. SwiftUI views
// continue to use @AppStorage(...) directly because that gives them automatic
// re-render on change — but everything *outside* the View layer (intents,
// services, widget data writers, tests) reads through here so the keys and
// defaults live in one place. Adding a new setting? Add the key constant +
// computed property here, then use @AppStorage(AppSettings.Key.xxx) in views.
enum AppSettings {

    enum Key {
        static let stockMode               = "stockMode"
        static let sharedFoodStock         = "sharedFoodStock"
        static let lowStockThreshold       = "lowStockThreshold"
        static let lowStockPushEnabled     = "lowStockPushEnabled"
        static let lowStockUIWarning       = "lowStockUIWarning"
        static let birthdayPushEnabled     = "birthdayPushEnabled"
        static let badgeEnabled            = "badgeEnabled"
        static let overduePushEnabled      = "overduePushEnabled"
        static let overdueThresholdHours   = "overdueThresholdHours"
        static let reminderMode            = "reminderMode"
        static let allDogsReminderTimesRaw = "allDogsReminderTimesRaw"
        static let needsReminderReschedule = "needsReminderReschedule"
        static let waterBowlReminderEnabled = "waterBowlReminderEnabled"
        static let waterBowlReminderWeekday = "waterBowlReminderWeekday"
        static let waterBowlReminderTime    = "waterBowlReminderTime"
        static let appearanceMode          = "appearanceMode"
        static let loggedByName            = "loggedByName"
    }

    // MARK: - Stock

    static var stockMode: StockMode {
        StockMode(rawValue: UserDefaults.standard.string(forKey: Key.stockMode) ?? "") ?? .none
    }

    static var sharedFoodStock: Int {
        get { UserDefaults.standard.integer(forKey: Key.sharedFoodStock) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: Key.sharedFoodStock) }
    }

    static var lowStockThreshold: Int {
        let stored = UserDefaults.standard.integer(forKey: Key.lowStockThreshold)
        return stored == 0 ? AppConstants.defaultLowStockThreshold : stored
    }

    static var lowStockPushEnabled: Bool {
        UserDefaults.standard.object(forKey: Key.lowStockPushEnabled) as? Bool ?? true
    }

    // MARK: - Notifications

    static var birthdayPushEnabled: Bool {
        UserDefaults.standard.object(forKey: Key.birthdayPushEnabled) as? Bool ?? true
    }

    static var badgeEnabled: Bool {
        UserDefaults.standard.object(forKey: Key.badgeEnabled) as? Bool ?? true
    }

    static var overduePushEnabled: Bool {
        UserDefaults.standard.object(forKey: Key.overduePushEnabled) as? Bool ?? true
    }

    static var overdueThresholdHours: Int {
        let stored = UserDefaults.standard.integer(forKey: Key.overdueThresholdHours)
        return stored == 0 ? AppConstants.defaultOverdueThresholdHours : max(1, stored)
    }

    // MARK: - Reminders

    static var reminderMode: ReminderMode {
        ReminderMode(rawValue: UserDefaults.standard.string(forKey: Key.reminderMode) ?? "") ?? .none
    }

    static var allDogsReminderTimes: [Int] {
        (UserDefaults.standard.string(forKey: Key.allDogsReminderTimesRaw) ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
    }

    static var needsReminderReschedule: Bool {
        get { UserDefaults.standard.bool(forKey: Key.needsReminderReschedule) }
        set { UserDefaults.standard.set(newValue, forKey: Key.needsReminderReschedule) }
    }
}
