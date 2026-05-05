import AppIntents
import SwiftData
import Foundation

struct PetEntity: AppEntity {
    static var defaultQuery = PetQuery()
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Dog"
    
    var id: UUID
    var name: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PetQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PetEntity] {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Pet>(predicate: #Predicate { identifiers.contains($0.id) })
        let pets = try context.fetch(descriptor)
        return pets.map { PetEntity(id: $0.id, name: $0.name ?? "Unknown") }
    }

    @MainActor
    func suggestedEntities() async throws -> [PetEntity] {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Pet>(sortBy: [SortDescriptor(\.name)])
        let pets = try context.fetch(descriptor)
        return pets.map { PetEntity(id: $0.id, name: $0.name ?? "Unknown") }
    }

    @MainActor
    func entities(matching string: String) async throws -> [PetEntity] {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Pet>(sortBy: [SortDescriptor(\.name)])
        let pets = try context.fetch(descriptor)
        return pets
            .filter { ($0.name ?? "").localizedCaseInsensitiveContains(string) }
            .map { PetEntity(id: $0.id, name: $0.name ?? "Unknown") }
    }
}