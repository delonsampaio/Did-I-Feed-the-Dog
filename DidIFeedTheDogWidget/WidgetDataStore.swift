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
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let pets = try? JSONDecoder().decode([PetWidgetData].self, from: data)
        else { return [] }
        return pets
    }

    static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }

    // Returns a short status string shown in debug builds to diagnose widget data issues
    static func debugStatus() -> String {
        guard let url = fileURL() else { return "no-group-container" }
        guard FileManager.default.fileExists(atPath: url.path) else { return "file-missing" }
        guard let data = try? Data(contentsOf: url) else { return "unreadable" }
        guard let pets = try? JSONDecoder().decode([PetWidgetData].self, from: data) else { return "bad-json" }
        return "\(pets.count) pets"
    }
}
