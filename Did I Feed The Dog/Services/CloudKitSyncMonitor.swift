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
                    // Extract the meaningful underlying error if it's a Code 2 (Partial Failure)
                    if let ckError = error as? CKError,
                       ckError.code == .partialFailure,
                       let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
                       let realError = partialErrors.values.first {
                        self?.lastError = realError
                    } else {
                        // Force the deep dictionary to be visible in the alert
                        let nsError = error as NSError
                        self?.lastError = DetailedSyncError(message: "\(nsError.domain) Code \(nsError.code)\n\n\(nsError.userInfo)")
                    }
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
