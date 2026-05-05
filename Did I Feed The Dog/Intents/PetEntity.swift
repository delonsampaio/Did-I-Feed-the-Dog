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

    // Ranks exact match > prefix match > substring match so misheard short
    // names ("Bus" → "Buster") still resolve, while "Daisy" picks Daisy over
    // "Daisy May" when both exist.
    @MainActor
    func entities(matching string: String) async throws -> [PetEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Pet>(sortBy: [SortDescriptor(\.name)])
        let pets = try context.fetch(descriptor)

        let scored: [(PetEntity, Int)] = pets.compactMap { pet in
            let name = pet.name ?? ""
            guard !name.isEmpty else { return nil }
            let score: Int
            if name.compare(needle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                score = 0
            } else if name.range(of: needle, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil {
                score = 1
            } else if name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                score = 2
            } else {
                return nil
            }
            return (PetEntity(id: pet.id, name: name), score)
        }

        return scored
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }
}
