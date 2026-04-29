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

    // Returns a short status string for diagnosing widget data issues
    static func debugStatus() -> String {
        guard let url = fileURL() else { return "no-group-container" }
        guard FileManager.default.fileExists(atPath: url.path) else { return "file-missing" }
        let mod = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let time = mod.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "?"
        guard let data = try? Data(contentsOf: url) else { return "unreadable @\(time)" }
        guard let pets = try? JSONDecoder().decode([PetWidgetData].self, from: data) else { return "bad-json @\(time)" }
        return "\(pets.count) pets @\(time)"
    }
}
