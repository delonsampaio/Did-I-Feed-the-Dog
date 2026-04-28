import AppIntents
import SwiftData

struct PetEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Dog")
    static var defaultQuery = PetEntityQuery()

    var id: UUID
    var name: String
    var foodStockCount: Int
    var lastFedTimestamp: Date?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(from pet: Pet) {
        self.id = pet.id
        self.name = pet.name ?? "Unknown"
        self.foodStockCount = pet.foodStockCount
        self.lastFedTimestamp = pet.lastFeedingEvent?.timestamp
    }
}

struct PetEntityQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [PetEntity] {
        guard let context = IntentDataAccess.makeContext() else { return [] }
        return IntentDataAccess.fetchPets(in: context)
            .filter { identifiers.contains($0.id) }
            .map { PetEntity(from: $0) }
    }

    func entities(matching string: String) async throws -> [PetEntity] {
        guard let context = IntentDataAccess.makeContext() else { return [] }
        return IntentDataAccess.fetchPets(in: context)
            .filter { ($0.name ?? "").localizedCaseInsensitiveContains(string) }
            .map { PetEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [PetEntity] {
        guard let context = IntentDataAccess.makeContext() else { return [] }
        return IntentDataAccess.fetchPets(in: context).map { PetEntity(from: $0) }
    }
}
