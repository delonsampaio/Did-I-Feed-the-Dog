import Foundation

// MUST stay byte-compatible with the duplicate definition in
// `Did I Feed The Dog/Utilities/WidgetDataWriter.swift`. The optional fields
// here exist only for graceful decode of snapshots written by older app
// versions; the current writer always emits non-nil values. Read the comment
// on the writer-side struct for the full contract.
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
        // UserDefaults first: writes to App Group UserDefaults are atomic,
        // so it always reflects the most recent successful WidgetDataWriter
        // write. The file write uses `try?` and silently swallows errors —
        // a failed file write leaves stale data on disk. Reading the file
        // first would return that stale snapshot even though UserDefaults
        // has the fresh one, which surfaced as "widget didn't refresh after
        // feed/delete/fasting toggle" in TestFlight (commit context: 2026-05-06).
        if let data = UserDefaults(suiteName: groupID)?.data(forKey: udKey),
           let pets = try? JSONDecoder().decode([PetWidgetData].self, from: data) {
            return pets
        }
        // Fall back to the JSON file only if UserDefaults is unavailable
        // (e.g. App Group misconfigured) or its payload didn't decode.
        if let url = fileURL(),
           let data = try? Data(contentsOf: url),
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
