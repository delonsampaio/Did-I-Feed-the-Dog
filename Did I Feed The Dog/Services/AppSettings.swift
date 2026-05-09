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
        static let stockOutSharedCount     = "stockOutSharedFeedingCount"
        static let stockOutIndividualCounts = "stockOutIndividualFeedingCountsJSON"
        static let stockOutPromptEnabled   = "stockOutPromptEnabled"
        static let isPro                   = "isPro"
        static let seenOverdueTeaseAt      = "seenOverdueTeaseAt"
        static let paywallShownFromPrefix  = "paywallShownFrom_"
        static let paywallConvertedFromPrefix = "paywallConvertedFrom_"
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

    /// Default ON. When OFF, the in-app "you're out of food" alert after a
    /// feeding is suppressed. The low-stock push notification is unaffected.
    static var stockOutPromptEnabled: Bool {
        sharedDefaults.object(forKey: Key.stockOutPromptEnabled) as? Bool ?? true
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

    // MARK: - Stock-Out Prompt Tracking
    //
    // We prompt the user to restock on the 1st, 4th, 7th... feeding while
    // stock is at 0 (every 3rd feeding after the first). The counter resets
    // whenever stock returns above 0 via any restock path.

    /// Step between consecutive stock-out prompts (count 1, 4, 7, 10, …).
    static let stockOutPromptStep = 3

    /// Increments the stock-out feeding counter for the given pet (nil → shared
    /// pool) and returns true if this feeding should trigger the restock prompt.
    @discardableResult
    static func recordFeedingAtZeroStock(petId: UUID?) -> Bool {
        let next = currentStockOutCount(petId: petId) + 1
        setStockOutCount(petId: petId, next)
        return next == 1 || (next - 1) % stockOutPromptStep == 0
    }

    /// Clears the counter when stock leaves 0 — call from any restock path.
    static func resetStockOutCount(petId: UUID?) {
        setStockOutCount(petId: petId, 0)
    }

    private static func currentStockOutCount(petId: UUID?) -> Int {
        guard let petId else { return sharedDefaults.integer(forKey: Key.stockOutSharedCount) }
        return individualStockOutCounts[petId.uuidString] ?? 0
    }

    private static func setStockOutCount(petId: UUID?, _ count: Int) {
        let clamped = max(0, count)
        guard let petId else {
            sharedDefaults.set(clamped, forKey: Key.stockOutSharedCount)
            return
        }
        var dict = individualStockOutCounts
        if clamped == 0 {
            dict.removeValue(forKey: petId.uuidString)
        } else {
            dict[petId.uuidString] = clamped
        }
        if let data = try? JSONEncoder().encode(dict) {
            sharedDefaults.set(data, forKey: Key.stockOutIndividualCounts)
        }
    }

    private static var individualStockOutCounts: [String: Int] {
        guard let data = sharedDefaults.data(forKey: Key.stockOutIndividualCounts),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return dict
    }

    // MARK: - Entitlement

    static var isPro: Bool {
        get { sharedDefaults.bool(forKey: Key.isPro) }
        set { sharedDefaults.set(newValue, forKey: Key.isPro) }
    }

    // MARK: - Overdue Tease

    static var seenOverdueTeaseAt: Date? {
        get {
            let ti = sharedDefaults.double(forKey: Key.seenOverdueTeaseAt)
            return ti == 0 ? nil : Date(timeIntervalSinceReferenceDate: ti)
        }
        set {
            sharedDefaults.set(newValue?.timeIntervalSinceReferenceDate ?? 0,
                               forKey: Key.seenOverdueTeaseAt)
        }
    }

    // MARK: - Telemetry

    static func incrementTelemetry(key: String) {
        let current = sharedDefaults.integer(forKey: key)
        sharedDefaults.set(current + 1, forKey: key)
    }
}
