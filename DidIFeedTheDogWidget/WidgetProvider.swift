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
        Task { @MainActor in
            completion(WidgetEntry(date: .now, pets: fetchPetSnapshots()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        Task { @MainActor in
            let entry = WidgetEntry(date: .now, pets: fetchPetSnapshots())
            let next  = Date().addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    @MainActor
    private static let sharedContainer: ModelContainer? = {
        let schema = Schema([Pet.self, FeedingEvent.self])
        let config = ModelConfiguration(
            schema: schema,
            allowsSave: false,
            groupContainer: .identifier("group.com.delon.DidIFeedTheDog")
        )
        return try? ModelContainer(for: schema, configurations: config)
    }()

    @MainActor
    private func fetchPetSnapshots() -> [PetSnapshot] {
        guard let container = Self.sharedContainer,
              let pets = try? container.mainContext.fetch(FetchDescriptor<Pet>())
        else { return [] }

        return pets
            .map { pet in
                let lastDate = pet.feedingEvents
                    .max(by: { $0.timestamp < $1.timestamp })?.timestamp
                return PetSnapshot(id: pet.id, name: pet.name,
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
