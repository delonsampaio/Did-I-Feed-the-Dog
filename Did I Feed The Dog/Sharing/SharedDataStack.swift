import CoreData
import Foundation
import os

/// Owns the Core Data container for shared dogs. Plain NSPersistentContainer (no
/// NSPersistentCloudKitContainer): the Phase 2 custom engine syncs this store to a
/// separate CloudKit container. Persistent history tracking is on so that engine can
/// detect local changes to push. Must never fatalError — a failure to open the shared
/// store must not break the app's private-data experience.
@Observable
final class SharedDataStack {

    static let shared = SharedDataStack()

    private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "SharedDataStack")
    private static let appGroupID = "group.com.delon.DidIFeedTheDog"
    private static let storeFileName = "SharedDogs.sqlite"

    private let container: NSPersistentContainer
    private(set) var loadError: Error?

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SharedDogs", managedObjectModel: SharedDataModel.makeModel())

        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else if let url = Self.storeURL() {
            description = NSPersistentStoreDescription(url: url)
        } else {
            description = NSPersistentStoreDescription()
            Self.log.error("Could not resolve app-group store URL; using default location")
        }
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { [weak self] _, error in
            if let error {
                Self.log.error("Shared store failed to load: \(error.localizedDescription, privacy: .public)")
                self?.loadError = error
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }

    private static func storeURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(storeFileName)
    }
}
