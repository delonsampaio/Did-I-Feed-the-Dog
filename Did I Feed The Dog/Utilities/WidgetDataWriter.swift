import Foundation
import ImageIO
import OSLog
import SwiftData
import WidgetKit

private let widgetLogger = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "WidgetWriter")

// MUST stay byte-compatible with the duplicate definition in
// `DidIFeedTheDogWidget/WidgetDataStore.swift`. The two targets can't share a
// type without project-file gymnastics, so the contract is: every field here
// has the same name + Codable shape as the widget side. The widget side keeps
// `isFasting`/`scheduleTimes`/`thresholdHours` Optional purely for back-compat
// with any encoded snapshots from older app versions; the writer never emits
// nil for them today. If you add a field, mirror it on the widget side and
// add a round-trip test (FeedingLogServiceTests.testWidgetSnapshotRoundTrip).
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

        let modeRaw = AppSettings.reminderMode.rawValue
        let allDogsTimes = AppSettings.allDogsReminderTimes.sorted()
        let threshold = AppSettings.overdueThresholdHours

        let eventsByPetId = events.map { Dictionary(grouping: $0, by: { $0.pet?.id ?? UUID() }) }

        snapshots = pets.map { pet in
            let lastDate: Date?
            if let byPetId = eventsByPetId {
                lastDate = (byPetId[pet.id] ?? []).max(by: { $0.timestamp < $1.timestamp })?.timestamp
            } else {
                lastDate = (pet.feedingEvents ?? []).max(by: { $0.timestamp < $1.timestamp })?.timestamp
            }

            let times = modeRaw == "allDogs" ? allDogsTimes : (modeRaw == "perDog" ? pet.feedingScheduleTimes.sorted() : [])

            return PetWidgetData(id: pet.id, name: pet.name ?? "Unknown",
                                 photoData: smallAvatarJPEG(from: pet.photoData), lastFedDate: lastDate,
                                 isFasting: pet.isFasting, scheduleTimes: times, thresholdHours: threshold)
        }

        guard let data = try? JSONEncoder().encode(snapshots) else {
            widgetLogger.error("Failed to encode widget snapshots.")
            return
        }

        // Move file I/O off the main thread to prevent frame drops
        Task.detached(priority: .utility) {
            if let url = fileURL() {
                do {
                    try data.write(to: url)
                } catch {
                    widgetLogger.error("Failed to write widget data to disk: \(error.localizedDescription, privacy: .public)")
                }
            }
            UserDefaults(suiteName: groupID)?.set(data, forKey: udKey)
            await MainActor.run {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    // Fetches both pets and events explicitly so no stale lazy loads.
    static func write(from context: ModelContext) {
        do {
            try context.save()
        } catch {
            widgetLogger.error("Pre-widget-write save failed: \(error.localizedDescription, privacy: .public)")
        }
        let pets: [Pet]
        let events: [FeedingEvent]
        do {
            pets = try context.fetch(FetchDescriptor<Pet>())

            // Only fetch recent events to prevent unbounded memory growth over time
            let limitDate = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
            let recentPredicate = #Predicate<FeedingEvent> { $0.timestamp > limitDate }
            events = try context.fetch(FetchDescriptor<FeedingEvent>(predicate: recentPredicate))
        } catch {
            widgetLogger.error("Pet/event fetch for widget snapshot failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        write(pets, events: events)
    }

    static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }

    // Downsamples a stored avatar to a tiny JPEG before persisting to the
    // widget store. Camera/Photos images can be 2–5 MB each; loading 6 of
    // those in the Large widget pushes the extension past iOS's hard 30 MB
    // memory cap and iOS jetsams the extension (redacted placeholder).
    // 360px max dimension covers a 30pt avatar @3x retina with headroom.
    private static func smallAvatarJPEG(from data: Data?, maxPixel: CGFloat = 360) -> Data? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let destOptions = [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, destOptions)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
