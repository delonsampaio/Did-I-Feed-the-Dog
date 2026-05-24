import WidgetKit
import Foundation

// Widget-extension-local tuning knobs. Mirrors values in the app's
// AppConstants — the two targets can't share Swift types without project-file
// changes, so keep these in lockstep manually.
enum WidgetTuning {
    static let refreshInterval: TimeInterval = 3600
    static let maxFutureEntries = 5
    static let groupID = "group.com.delon.DidIFeedTheDog"
}

private func readIsPro() -> Bool {
    UserDefaults(suiteName: WidgetTuning.groupID)?.bool(forKey: "isPro") ?? false
}

struct Provider: TimelineProvider {

    func placeholder(in context: Context) -> WidgetEntry {
        // Prefer the user's actual dogs (gallery preview personalizes nicely);
        // fall back to a fixed "Max"/"Bailey" pair before any pets are added.
        let real = Self.fetchPetSnapshots()
        if !real.isEmpty {
            return WidgetEntry(date: .now, pets: real, isPro: readIsPro())
        }
        let now = Date()
        return WidgetEntry(date: now, pets: [
            PetSnapshot(data: PetWidgetData(id: UUID(), name: "Max", photoData: nil,
                        lastFedDate: now.addingTimeInterval(-1800), isFasting: false, scheduleTimes: [], thresholdHours: 12, hasMedicationDue: false)),
            PetSnapshot(data: PetWidgetData(id: UUID(), name: "Bailey", photoData: nil,
                        lastFedDate: now.addingTimeInterval(-32400), isFasting: false, scheduleTimes: [], thresholdHours: 12, hasMedicationDue: false))
        ], isPro: readIsPro())
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: .now, pets: Self.fetchPetSnapshots(), isPro: readIsPro()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let petsData = WidgetDataStore.load()
        let now = Date()
        let isPro = readIsPro()

        var entries: [WidgetEntry] = []
        entries.append(WidgetEntry(date: now, pets: Self.fetchPetSnapshots(data: petsData, at: now), isPro: isPro))

        // Schedule extra entries at the moments dogs would flip overdue, so
        // the widget visually changes state without waiting for the hourly
        // refresh policy.
        var futureDates = Set<Date>()
        for pet in petsData {
            if let nextDate = PetSnapshot.nextOverdueDate(for: pet, after: now) {
                futureDates.insert(nextDate)
            }
            if let nextMedDate = pet.nextMedicationDueDate, nextMedDate > now {
                futureDates.insert(nextMedDate)
            }
        }

        let sortedFutureDates = futureDates.sorted().prefix(WidgetTuning.maxFutureEntries)
        for date in sortedFutureDates {
            entries.append(WidgetEntry(date: date, pets: Self.fetchPetSnapshots(data: petsData, at: date), isPro: isPro))
        }

        let next = now.addingTimeInterval(WidgetTuning.refreshInterval)
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private static func fetchPetSnapshots(data: [PetWidgetData]? = nil, at date: Date = .now) -> [PetSnapshot] {
        let pets = data ?? WidgetDataStore.load()
        return pets
            .map { PetSnapshot(data: $0, at: date) }
            .sorted { a, b in
                // Surface the most critical dogs first: Overdue → Fasting →
                // Fed. Within a category, oldest lastFedDate first so users
                // see the longest-untended dog at the top.
                let aCategory = a.isFeedingOverdue ? 0 : (a.isFasting ? 1 : 2)
                let bCategory = b.isFeedingOverdue ? 0 : (b.isFasting ? 1 : 2)
                if aCategory != bCategory { return aCategory < bCategory }

                switch (a.lastFedDate, b.lastFedDate) {
                case (nil, nil): return a.name < b.name
                case (nil, _): return true
                case (_, nil): return false
                case let (d1?, d2?):
                    if d1 == d2 { return a.name < b.name }
                    return d1 < d2
                }
            }
    }
}
