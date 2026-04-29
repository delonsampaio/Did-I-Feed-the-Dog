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

    @State private var deepLinkPetId: UUID? = nil

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkPetId: $deepLinkPetId)
                .background(WidgetRefresher())
                .task {
                    await NotificationManager.shared.requestAuthorization()
                }
                .task(id: "timer-diagnostic") {
                    // Sentinel: -1 = not yet run, 0 = ran but store empty, N = found dogs
                    let ud = UserDefaults(suiteName: WidgetDataWriter.groupID)
                    ud?.set(-1, forKey: "debugPetsCount_timer5")
                    try? await Task.sleep(for: .seconds(5))
                    let pets = (try? sharedModelContainer.mainContext.fetch(FetchDescriptor<Pet>())) ?? []
                    ud?.set(pets.count, forKey: "debugPetsCount_timer5")
                    guard !pets.isEmpty else { return }
                    WidgetDataWriter.write(pets)
                }
                .onOpenURL { url in
                    deepLinkPetId = parseDeepLink(url)
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSNotification.Name.NSPersistentStoreRemoteChange)
                ) { _ in
                    Task { @MainActor in
                        let ud = UserDefaults(suiteName: WidgetDataWriter.groupID)
                        ud?.set(-1, forKey: "debugPetsCount_cloudkit")
                        try? await Task.sleep(for: .seconds(3))
                        let pets = (try? sharedModelContainer.mainContext.fetch(FetchDescriptor<Pet>())) ?? []
                        ud?.set(pets.count, forKey: "debugPetsCount_cloudkit")
                        guard !pets.isEmpty else { return }
                        WidgetDataWriter.write(pets)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
