import Foundation

struct PetWidgetData: Codable {
    let id: UUID
    let name: String
    let photoData: Data?
    let lastFedDate: Date?
    let isFasting: Bool?
    let scheduleTimes: [Int]?
    let thresholdHours: Int?
}

enum WidgetDataStore {
    private static let groupID  = "group.com.delon.DidIFeedTheDog"
    private static let fileName = "widgetPetData.json"
    private static let udKey    = "widgetPetData"

    static func load() -> [PetWidgetData] {
        // Try file first
        if let url = fileURL(),
           let data = try? Data(contentsOf: url),
           let pets = try? JSONDecoder().decode([PetWidgetData].self, from: data) {
            return pets
        }
        // Fall back to UserDefaults
        if let data = UserDefaults(suiteName: groupID)?.data(forKey: udKey),
           let pets = try? JSONDecoder().decode([PetWidgetData].self, from: data) {
            return pets
        }
        return []
    }

    static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }
}
