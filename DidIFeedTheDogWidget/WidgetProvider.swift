import WidgetKit
import Foundation

struct Provider: TimelineProvider {

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, pets: [
            PetSnapshot(data: PetWidgetData(id: UUID(), name: "Max", photoData: nil,
                        lastFedDate: Date().addingTimeInterval(-1800), isFasting: false, scheduleTimes: [], thresholdHours: 12)),
            PetSnapshot(data: PetWidgetData(id: UUID(), name: "Bailey", photoData: nil,
                        lastFedDate: Date().addingTimeInterval(-32400), isFasting: false, scheduleTimes: [], thresholdHours: 12))
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: .now, pets: Self.fetchPetSnapshots()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = WidgetEntry(date: .now, pets: Self.fetchPetSnapshots())
        let next  = Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private static func fetchPetSnapshots() -> [PetSnapshot] {
        let pets = WidgetDataStore.load()
        return pets
            .map { PetSnapshot(data: $0) }
            .sorted { a, b in
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
