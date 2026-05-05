import Foundation

// Centralized tuning knobs. Pulled from values that were previously inlined
// across the codebase. If a value needs to be user-configurable, expose it
// through AppSettings and read the AppStorage value with this constant as
// the fallback default.
enum AppConstants {
    // MARK: - Stock & feeding

    static let defaultLowStockThreshold = 5
    static let defaultOverdueThresholdHours = 12
    static let perPetStockCap = 999
    static let sharedStockCap = 9999
    static let maxReminderTimesPerSchedule = 3

    // MARK: - Avatar / photo compression

    static let photoMaxDimensionPoints: CGFloat = 1024
    static let photoMaxJPEGBytes = 500_000
    static let photoJPEGQualityFloor: CGFloat = 0.2
    static let photoJPEGQualityStart: CGFloat = 0.8
    static let photoJPEGQualityStep: CGFloat = 0.15

    // MARK: - UI timing

    static let undoToastSeconds: Double = 4.0
    static let lowStockNotificationDelaySeconds: Double = 30.0
    static let pullToRefreshSettleMilliseconds: Int = 600

    // MARK: - Quick Actions / Shortcuts

    /// iOS limits Home Screen Quick Actions to 4 items.
    static let maxQuickActions = 4

    // MARK: - Widget

    static let widgetTimelineRefreshInterval: TimeInterval = 3600
    static let widgetMaxFutureEntries = 5
}
