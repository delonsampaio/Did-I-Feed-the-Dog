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
        }
        .modelContainer(sharedModelContainer)
    }
}
