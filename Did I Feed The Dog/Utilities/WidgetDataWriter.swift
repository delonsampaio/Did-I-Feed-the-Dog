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
    private static let suiteName = "group.com.delon.DidIFeedTheDog"
    private static let key = "widgetPetData"

    static func write(from context: ModelContext) {
        try? context.save()
        let pets = (try? context.fetch(FetchDescriptor<Pet>())) ?? []
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
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults(suiteName: suiteName)?.set(data, forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
