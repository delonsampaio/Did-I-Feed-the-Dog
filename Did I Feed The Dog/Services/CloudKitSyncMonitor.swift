import CoreData
import Foundation

@Observable
final class CloudKitSyncMonitor {
    private(set) var isSyncing = false
    private(set) var lastError: Error?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            
            self?.isSyncing = event.endDate == nil
            
            if event.endDate != nil {
                if let error = event.error {
                    self?.lastError = error
                    print("CloudKit Sync Error: \(error.localizedDescription)")
                } else if event.succeeded {
                    self?.lastError = nil
                }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
