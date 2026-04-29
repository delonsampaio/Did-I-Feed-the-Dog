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

    // Preferred: pass already-loaded pets directly from @Query to avoid
    // context.fetch() returning stale/empty results before SwiftData is ready.
    static func write(_ pets: [Pet]) {
        let snapshots = pets.map { pet -> PetWidgetData in
            let lastDate = (pet.feedingEvents ?? [])
                .max(by: { $0.timestamp < $1.timestamp })?.timestamp
            return PetWidgetData(
                id: pet.id,
                name: pet.name ?? "Unknown",
                photoData: pet.photoData,
                lastFedDate: lastDate
            )
        }
        guard let url = fileURL() else { return }
        if let data = try? JSONEncoder().encode(snapshots) {
            try? data.write(to: url, options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // Fallback for callers that don't have an already-loaded pet list.
    static func write(from context: ModelContext) {
        try? context.save()
        let pets = (try? context.fetch(FetchDescriptor<Pet>())) ?? []
        write(pets)
    }

    static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }
}
