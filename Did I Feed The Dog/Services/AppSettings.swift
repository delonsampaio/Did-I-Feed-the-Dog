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

    static let sharedDefaults = UserDefaults(suiteName: "group.com.delon.DidIFeedTheDog") ?? .standard

    // MARK: - Stock

    static var stockMode: StockMode {
        StockMode(rawValue: sharedDefaults.string(forKey: Key.stockMode) ?? "") ?? .individual
    }

    static var sharedFoodStock: Int {
        get { sharedDefaults.integer(forKey: Key.sharedFoodStock) }
        set { sharedDefaults.set(max(0, newValue), forKey: Key.sharedFoodStock) }
    }

    static var lowStockThreshold: Int {
        let stored = sharedDefaults.integer(forKey: Key.lowStockThreshold)
        return stored == 0 ? AppConstants.defaultLowStockThreshold : stored
    }

    static var lowStockPushEnabled: Bool {
        sharedDefaults.object(forKey: Key.lowStockPushEnabled) as? Bool ?? true
    }

    // MARK: - Notifications

    static var birthdayPushEnabled: Bool {
        sharedDefaults.object(forKey: Key.birthdayPushEnabled) as? Bool ?? true
    }

    static var badgeEnabled: Bool {
        sharedDefaults.object(forKey: Key.badgeEnabled) as? Bool ?? true
    }

    static var overduePushEnabled: Bool {
        sharedDefaults.object(forKey: Key.overduePushEnabled) as? Bool ?? true
    }

    static var overdueThresholdHours: Int {
        let stored = sharedDefaults.integer(forKey: Key.overdueThresholdHours)
        return stored == 0 ? AppConstants.defaultOverdueThresholdHours : max(1, stored)
    }

    // MARK: - Reminders

    static var reminderMode: ReminderMode {
        ReminderMode(rawValue: sharedDefaults.string(forKey: Key.reminderMode) ?? "") ?? .none
    }

    static var allDogsReminderTimes: [Int] {
        (sharedDefaults.string(forKey: Key.allDogsReminderTimesRaw) ?? "")
            .split(separator: ",")
            .compactMap { Int($0) }
    }

    static var needsReminderReschedule: Bool {
        get { sharedDefaults.bool(forKey: Key.needsReminderReschedule) }
        set { sharedDefaults.set(newValue, forKey: Key.needsReminderReschedule) }
    }
}
