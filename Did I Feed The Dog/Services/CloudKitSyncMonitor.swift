import CoreData
import Foundation
import CloudKit

struct DetailedSyncError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

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
                    if let ckError = error as? CKError, ckError.code == .partialFailure {
                        let partialErrors = (ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error]) ?? [:]
                        if let realError = partialErrors.values.first {
                            // A real partial failure with specific item errors
                            print("CloudKit Sync Error: \(realError.localizedDescription)")
                            self?.lastError = realError
                        } else {
                            // Empty partialErrors dict = NSPersistentCloudKitContainer no-op signal; treat as success
                            self?.lastError = nil
                        }
                    } else {
                        let nsError = error as NSError
                        print("CloudKit Sync Error: \(nsError.domain) \(nsError.code) \(nsError.userInfo)")
                        self?.lastError = DetailedSyncError(message: "\(nsError.domain) Code \(nsError.code)")
                    }
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
