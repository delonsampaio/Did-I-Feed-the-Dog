import WidgetKit
import Foundation

struct Provider: TimelineProvider {

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, pets: [
            PetSnapshot(id: UUID(), name: "Max",    photoData: nil,
                        lastFedDate: Date().addingTimeInterval(-1800)),
            PetSnapshot(id: UUID(), name: "Bailey", photoData: nil,
                        lastFedDate: Date().addingTimeInterval(-32400))
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
            .map { PetSnapshot(id: $0.id, name: $0.name, photoData: $0.photoData, lastFedDate: $0.lastFedDate) }
            .sorted { a, b in
                switch (a.lastFedDate, b.lastFedDate) {
                case (nil, _): return true
                case (_, nil): return false
                case let (d1?, d2?): return d1 < d2
                }
            }
    }
}
