import SwiftData
import Foundation

enum IntentDataAccess {
    static let container: ModelContainer? = {
        let schema = Schema([Pet.self, FeedingEvent.self])
        let config = ModelConfiguration(
            schema: schema,
            allowsSave: true,
            groupContainer: .identifier("group.com.delon.DidIFeedTheDog"),
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, configurations: [config])
    }()

    static func makeContext() -> ModelContext? {
        guard let container else { return nil }
        return ModelContext(container)
    }

    static func fetchPets(in context: ModelContext) -> [Pet] {
        let descriptor = FetchDescriptor<Pet>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }
}
