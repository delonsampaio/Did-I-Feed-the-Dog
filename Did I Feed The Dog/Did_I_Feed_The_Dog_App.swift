import Combine
import CoreData
import SwiftUI
import SwiftData

@main
struct Did_I_Feed_The_Dog_App: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([Pet.self, FeedingEvent.self])
        let config = ModelConfiguration(
            "DogFeedStore",
            schema: schema,
            allowsSave: true,
            groupContainer: .identifier("group.com.delon.DidIFeedTheDog"),
            cloudKitDatabase: .automatic
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            container.mainContext.autosaveEnabled = true
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @Environment(\.scenePhase) private var scenePhase
    @State private var deepLinkPetId: UUID? = nil

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkPetId: $deepLinkPetId)
                .task {
                    await NotificationManager.shared.requestAuthorization()
                }
                .task(id: "timer-diagnostic") {
                    let ud = UserDefaults(suiteName: WidgetDataWriter.groupID)
                    ud?.set(-1, forKey: "debugPetsCount_timer5")
                    try? await Task.sleep(for: .seconds(5))
                    // Fresh context bypasses any mainContext in-memory cache
                    let ctx = ModelContext(sharedModelContainer)
                    let pets   = (try? ctx.fetch(FetchDescriptor<Pet>())) ?? []
                    let events = (try? ctx.fetch(FetchDescriptor<FeedingEvent>())) ?? []
                    ud?.set(pets.count, forKey: "debugPetsCount_timer5")
                    guard !pets.isEmpty else { return }
                    WidgetDataWriter.write(pets, events: events)
                }
                .onOpenURL { url in
                    deepLinkPetId = parseDeepLink(url)
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSNotification.Name.NSPersistentStoreRemoteChange)
                        .receive(on: DispatchQueue.main)
                ) { _ in
                    Task { @MainActor in
                        let ud = UserDefaults(suiteName: WidgetDataWriter.groupID)
                        ud?.set(-1, forKey: "debugPetsCount_cloudkit")
                        try? await Task.sleep(for: .seconds(3))
                        let ctx = ModelContext(sharedModelContainer)
                        let pets   = (try? ctx.fetch(FetchDescriptor<Pet>())) ?? []
                        let events = (try? ctx.fetch(FetchDescriptor<FeedingEvent>())) ?? []
                        ud?.set(pets.count, forKey: "debugPetsCount_cloudkit")
                        guard !pets.isEmpty else { return }
                        WidgetDataWriter.write(pets, events: events)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                let ctx = ModelContext(sharedModelContainer)
                let pets   = (try? ctx.fetch(FetchDescriptor<Pet>())) ?? []
                let events = (try? ctx.fetch(FetchDescriptor<FeedingEvent>())) ?? []
                UserDefaults(suiteName: WidgetDataWriter.groupID)?
                    .set(pets.count, forKey: "debugPetsCount_scene")
                guard !pets.isEmpty else { return }
                WidgetDataWriter.write(pets, events: events)
            }
        }
    }
}
