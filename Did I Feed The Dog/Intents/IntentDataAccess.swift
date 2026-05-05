import SwiftData
import Foundation

// AppIntents always read/write through `sharedModelContainer.mainContext` so
// that they share the CloudKit-enabled container with the app. Creating a
// second container against the same store registers duplicate CKScheduler
// handlers and breaks sync.
enum IntentDataAccess {
    static var container: ModelContainer { sharedModelContainer }

    static func fetchPets(in context: ModelContext) -> [Pet] {
        let descriptor = FetchDescriptor<Pet>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }
}
