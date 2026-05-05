import CoreData
import Foundation
import OSLog

@Observable
final class CloudKitSyncMonitor {
    private(set) var isSyncing = false
    /// Last sync error surfaced by NSPersistentCloudKitContainer. Cleared on
    /// the next successful sync. The dashboard reads this to surface a
    /// non-blocking warning so users learn when their data isn't reaching
    /// iCloud (instead of the previous "always green checkmark" lie).
    private(set) var lastError: Error?

    private var observer: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "CloudKitSync")

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                  ] as? NSPersistentCloudKitContainer.Event
            else { return }

            self.isSyncing = event.endDate == nil

            // Only inspect errors on completed events (in-progress events
            // don't have a meaningful state yet).
            if event.endDate != nil {
                if let error = event.error {
                    self.lastError = error
                    self.logger.error(
                        "CloudKit \(String(describing: event.type), privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                    )
                } else if event.succeeded {
                    self.lastError = nil
                }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
