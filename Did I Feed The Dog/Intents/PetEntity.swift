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
            print("[SiriDebug] defaultResult() -> auto-returning only pet '\(only.name ?? "Unknown")'")
            return PetEntity(id: only.id, name: only.name ?? "Unknown")
        }
        print("[SiriDebug] defaultResult() -> returning nil (\(pets.count) pets, will prompt)")
        return nil
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PetEntity] {
        print("[SiriDebug] entities(for:) called with identifiers: \(identifiers)")
        let context = sharedModelContainer.mainContext

        // SwiftData predicates using `.contains` are notoriously buggy and often return all records.
        // Fetching all and filtering in-memory guarantees we only return the exact dog Siri asked for.
        let descriptor = FetchDescriptor<Pet>()
        let allPets = try context.fetch(descriptor)
        let result = allPets
            .filter { identifiers.contains($0.id) }
            .map { PetEntity(id: $0.id, name: $0.name ?? "Unknown") }
        print("[SiriDebug] entities(for:) returning: \(result.map { $0.name })")
        return result
    }

    @MainActor
    func suggestedEntities() async throws -> [PetEntity] {
        print("[SiriDebug] suggestedEntities() called")
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Pet>(sortBy: [SortDescriptor(\.name)])
        let pets = try context.fetch(descriptor)
        let result = pets.map { PetEntity(id: $0.id, name: $0.name ?? "Unknown") }
        print("[SiriDebug] suggestedEntities() returning: \(result.map { $0.name })")
        return result
    }

    // Ranks exact match > prefix match > substring match so misheard short
    // names ("Bus" → "Buster") still resolve, while "Daisy" picks Daisy over
    // "Daisy May" when both exist.
    @MainActor
    func entities(matching string: String) async throws -> [PetEntity] {
        print("[SiriDebug] entities(matching:) called with raw string: '\(string)'")
        // Siri often accidentally includes the possessive 's in the search string.
        let needle = string
            .replacingOccurrences(of: "'s", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "’s", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        print("[SiriDebug] entities(matching:) normalized needle: '\(needle)'")

        guard !needle.isEmpty else {
            print("[SiriDebug] entities(matching:) returning [] (empty needle)")
            return []
        }

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

        let result = scored
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
        print("[SiriDebug] entities(matching:) returning: \(result.map { $0.name }) (from needle '\(needle)')")
        return result
    }
}
