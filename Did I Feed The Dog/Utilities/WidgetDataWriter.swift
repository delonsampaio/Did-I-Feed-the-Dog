import Foundation
import SwiftData
import WidgetKit

struct PetWidgetData: Codable {
    let id: UUID
    let name: String
    let photoData: Data?
    let lastFedDate: Date?
    let isFasting: Bool
    let scheduleTimes: [Int]
    let thresholdHours: Int
}

enum WidgetDataWriter {
    private static let groupID  = "group.com.delon.DidIFeedTheDog"
    private static let fileName = "widgetPetData.json"
    private static let udKey    = "widgetPetData"

    // Pass explicit events to avoid stale lazy-relationship data.
    static func write(_ pets: [Pet], events: [FeedingEvent]? = nil) {
        let snapshots: [PetWidgetData]
        
        let modeRaw = UserDefaults.standard.string(forKey: "reminderMode") ?? ""
        let allDogsTimes = (UserDefaults.standard.string(forKey: "allDogsReminderTimesRaw") ?? "")
            .split(separator: ",").compactMap { Int($0) }.sorted()
        let threshold = max(1, UserDefaults.standard.integer(forKey: "overdueThresholdHours"))

        if let events = events {
            let byPetId = Dictionary(grouping: events, by: { $0.pet?.id ?? UUID() })
            snapshots = pets.map { pet in
                let lastDate = (byPetId[pet.id] ?? [])
                    .max(by: { $0.timestamp < $1.timestamp })?.timestamp
                
                let times = modeRaw == "allDogs" ? allDogsTimes : (modeRaw == "perDog" ? pet.feedingScheduleTimes.sorted() : [])
                
                return PetWidgetData(id: pet.id, name: pet.name ?? "Unknown",
                                     photoData: pet.photoData, lastFedDate: lastDate,
                                     isFasting: pet.isFasting, scheduleTimes: times, thresholdHours: threshold)
            }
        } else {
            snapshots = pets.map { pet in
                let lastDate = (pet.feedingEvents ?? [])
                    .max(by: { $0.timestamp < $1.timestamp })?.timestamp
                    
                let times = modeRaw == "allDogs" ? allDogsTimes : (modeRaw == "perDog" ? pet.feedingScheduleTimes.sorted() : [])

                return PetWidgetData(id: pet.id, name: pet.name ?? "Unknown",
                                     photoData: pet.photoData, lastFedDate: lastDate,
                                     isFasting: pet.isFasting, scheduleTimes: times, thresholdHours: threshold)
            }
        }

        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        if let url = fileURL() { try? data.write(to: url) }
        UserDefaults(suiteName: groupID)?.set(data, forKey: udKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // Fetches both pets and events explicitly so no stale lazy loads.
    static func write(from context: ModelContext) {
        try? context.save()
        let pets = (try? context.fetch(FetchDescriptor<Pet>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<FeedingEvent>())) ?? []
        write(pets, events: events)
    }

    static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }
}
