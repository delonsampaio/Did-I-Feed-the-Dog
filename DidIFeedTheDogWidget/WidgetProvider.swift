// DidIFeedTheDogWidget/WidgetProvider.swift
import WidgetKit
import SwiftData

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

    // A fresh ModelContext per call avoids any main-actor requirement.
    private static let sharedContainer: ModelContainer? = {
        let schema = Schema([Pet.self, FeedingEvent.self])
        let config = ModelConfiguration(
            schema: schema,
            allowsSave: false,
            groupContainer: .identifier("group.com.delon.DidIFeedTheDog"),
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, configurations: config)
    }()

    private static func fetchPetSnapshots() -> [PetSnapshot] {
        guard let container = sharedContainer else { return [] }
        let context = ModelContext(container)
        let pets = (try? context.fetch(FetchDescriptor<Pet>())) ?? []
        return pets
            .map { pet in
                let lastDate = (pet.feedingEvents ?? [])
                    .max(by: { $0.timestamp < $1.timestamp })?.timestamp
                return PetSnapshot(id: pet.id, name: pet.name ?? "Unknown",
                                   photoData: pet.photoData, lastFedDate: lastDate)
            }
            .sorted { a, b in
                switch (a.lastFedDate, b.lastFedDate) {
                case (nil, _): return true
                case (_, nil): return false
                case let (d1?, d2?): return d1 < d2
                }
            }
    }
}
