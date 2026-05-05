import Foundation

/// Snapshot of settings needed to compute `isFeedingOverdue`. Building the
/// snapshot once per render and passing it to N pets avoids re-reading
/// UserDefaults inside the SwiftData property accessor on every redraw.
struct OverdueContext {
    let reminderMode: ReminderMode
    let allDogsReminderTimes: [Int]
    let overdueThresholdHours: Int

    static var current: OverdueContext {
        OverdueContext(
            reminderMode: AppSettings.reminderMode,
            allDogsReminderTimes: AppSettings.allDogsReminderTimes,
            overdueThresholdHours: AppSettings.overdueThresholdHours
        )
    }
}
