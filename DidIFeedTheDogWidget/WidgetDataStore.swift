import Foundation

struct PetWidgetData: Codable {
    let id: UUID
    let name: String
    let photoData: Data?
    let lastFedDate: Date?
}

enum WidgetDataStore {
    private static let groupID = "group.com.delon.DidIFeedTheDog"
    private static let fileName = "widgetPetData.json"

    static func load() -> [PetWidgetData] {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let pets = try? JSONDecoder().decode([PetWidgetData].self, from: data)
        else { return [] }
        return pets
    }
}
