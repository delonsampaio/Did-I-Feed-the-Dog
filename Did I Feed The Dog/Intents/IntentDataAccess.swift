import SwiftData
import Foundation

enum IntentDataAccess {
    // Reuse the app's shared container. Creating a second CloudKit-enabled
    // container against the same store causes CloudKit handler registration
    // conflicts and breaks sync.
    static var container: ModelContainer? { sharedModelContainer }

    static func makeContext() -> ModelContext? {
        ModelContext(sharedModelContainer)
    }

    static func fetchPets(in context: ModelContext) -> [Pet] {
        let descriptor = FetchDescriptor<Pet>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }
}
