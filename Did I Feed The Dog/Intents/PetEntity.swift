import AppIntents
import SwiftData
import Foundation

struct PetEntity: AppEntity {
    static var defaultQuery = PetQuery()
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Dog"

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            synonyms: [
                "\(name)'s",
                "\(name)’s"
            ]
        )
    }
}

struct PetQuery: EntityQuery, EntityStringQuery {
    // Single-pet households auto-resolve to the only dog so Siri doesn't ask
    // "Which dog?" when there's literally only one option. Multi-pet households
    // get nil here, which forces Siri to prompt via the picker.
    @MainActor
    func defaultResult() async -> PetEntity? {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Pet>()
        let pets = (try? context.fetch(descriptor)) ?? []
        if pets.count == 1, let only = pets.first {
            return PetEntity(id: only.id, name: only.name ?? "Unknown")
        }
        return nil
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PetEntity] {
        let context = sharedModelContainer.mainContext

        // SwiftData predicates using `.contains` are notoriously buggy and often return all records.
        // Fetching all and filtering in-memory guarantees we only return the exact dog Siri asked for.
        let descriptor = FetchDescriptor<Pet>()
        let allPets = try context.fetch(descriptor)
        return allPets
            .filter { identifiers.contains($0.id) }
            .map { PetEntity(id: $0.id, name: $0.name ?? "Unknown") }
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
        // Siri often accidentally includes the possessive 's in the search string.
        let needle = string
            .replacingOccurrences(of: "'s", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "’s", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !needle.isEmpty else { return [] }

        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Pet>(sortBy: [SortDescriptor(\.name)])
        let pets = try context.fetch(descriptor)

        let scored: [(PetEntity, Int)] = pets.compactMap { pet in
            let name = (pet.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let score: Int
            if name.compare(needle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                score = 0
            } else if name.range(of: needle, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil {
                score = 1
            } else if name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                score = 2
            // Reverse check: if Siri captured "Luna Bear" but the dog's name is just "Luna"
            } else if needle.range(of: name, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil {
                score = 3
            } else {
                return nil
            }
            return (PetEntity(id: pet.id, name: name), score)
        }

        // Return only the best-scoring tier so Siri auto-resolves when one
        // dog clearly wins. Returning multiple matches causes Siri to re-show
        // the picker even after the user said a name.
        guard let bestScore = scored.map(\.1).min() else { return [] }
        return scored
            .filter { $0.1 == bestScore }
            .sorted { $0.0.name < $1.0.name }
            .map { $0.0 }
    }
}
