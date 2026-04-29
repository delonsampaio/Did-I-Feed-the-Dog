import Foundation

struct PetWidgetData: Codable {
    let id: UUID
    let name: String
    let photoData: Data?
    let lastFedDate: Date?
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

    static func debugStatus() -> String {
        var parts: [String] = []

        // Check file
        if let url = fileURL() {
            if FileManager.default.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let pets = try? JSONDecoder().decode([PetWidgetData].self, from: data) {
                let mod = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
                let t = mod.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? "?"
                parts.append("file:\(pets.count)@\(t)")
            } else {
                parts.append("file:missing")
            }
        } else {
            parts.append("no-container")
        }

        // Check UserDefaults
        if let data = UserDefaults(suiteName: groupID)?.data(forKey: udKey),
           let pets = try? JSONDecoder().decode([PetWidgetData].self, from: data) {
            parts.append("ud:\(pets.count)")
        } else {
            parts.append("ud:none")
        }

        return parts.joined(separator: " ")
    }
}
