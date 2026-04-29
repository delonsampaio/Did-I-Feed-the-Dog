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
                .onOpenURL { url in
                    deepLinkPetId = parseDeepLink(url)
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSNotification.Name.NSPersistentStoreRemoteChange)
                ) { _ in
                    Task { @MainActor in
                        // Give the main context time to merge CloudKit changes
                        try? await Task.sleep(for: .milliseconds(500))
                        let ctx = sharedModelContainer.mainContext
                        let pets = (try? ctx.fetch(FetchDescriptor<Pet>())) ?? []
                        UserDefaults(suiteName: WidgetDataWriter.groupID)?
                            .set(pets.count, forKey: "debugPetsCount_cloudkit")
                        guard !pets.isEmpty else { return }
                        WidgetDataWriter.write(pets)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
