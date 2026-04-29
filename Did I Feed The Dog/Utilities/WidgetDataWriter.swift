import Foundation
import SwiftData
import WidgetKit

struct PetWidgetData: Codable {
    let id: UUID
    let name: String
    let photoData: Data?
    let lastFedDate: Date?
}

enum WidgetDataWriter {
    static let groupID = "group.com.delon.DidIFeedTheDog"
    static let fileName = "widgetPetData.json"
    static let udKey    = "widgetPetData"

    // Pass explicit events to avoid stale lazy-relationship data.
    static func write(_ pets: [Pet], events: [FeedingEvent]? = nil) {
        let snapshots: [PetWidgetData]

        if let events = events {
            let byPetId = Dictionary(grouping: events, by: { $0.pet?.id ?? UUID() })
            snapshots = pets.map { pet in
                let lastDate = (byPetId[pet.id] ?? [])
                    .max(by: { $0.timestamp < $1.timestamp })?.timestamp
                return PetWidgetData(id: pet.id, name: pet.name ?? "Unknown",
                                     photoData: pet.photoData, lastFedDate: lastDate)
            }
        } else {
            snapshots = pets.map { pet in
                let lastDate = (pet.feedingEvents ?? [])
                    .max(by: { $0.timestamp < $1.timestamp })?.timestamp
                return PetWidgetData(id: pet.id, name: pet.name ?? "Unknown",
                                     photoData: pet.photoData, lastFedDate: lastDate)
            }
        }

        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        if let url = fileURL() { try? data.write(to: url) }
        UserDefaults(suiteName: groupID)?.set(data, forKey: udKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // Fetches both pets and events explicitly so no stale lazy loads.
    static func write(from context: ModelContext) {
        try? context.save()
        let pets = (try? context.fetch(FetchDescriptor<Pet>())) ?? []
        guard !pets.isEmpty else { return }
        let events = (try? context.fetch(FetchDescriptor<FeedingEvent>())) ?? []
        write(pets, events: events)
    }

    static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }
}
