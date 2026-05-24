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
    let hasMedicationDue: Bool?
    let nextMedicationDueDate: Date?
}

enum WidgetDataStore {
    private static let groupID  = "group.com.delon.DidIFeedTheDog"
    private static let udKey    = "widgetPetData"

    static func load() -> [PetWidgetData] {
        // Read from UserDefaults only - App Group UserDefaults is backed by plist
        // and natively handles atomic, cross-process read/write safety.
        // Removed redundant JSON file to eliminate race conditions.
        if let data = UserDefaults(suiteName: groupID)?.data(forKey: udKey),
           let pets = try? JSONDecoder().decode([PetWidgetData].self, from: data) {
            return pets
        }
        return []
    }
}
