import Foundation

struct PetWidgetData: Codable {
    let id: UUID
    let name: String
    let photoData: Data?
    let lastFedDate: Date?
}

enum WidgetDataStore {
    private static let suiteName = "group.com.delon.DidIFeedTheDog"
    private static let key = "widgetPetData"

    static func load() -> [PetWidgetData] {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key),
              let pets = try? JSONDecoder().decode([PetWidgetData].self, from: data)
        else { return [] }
        return pets
    }
}
