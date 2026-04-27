import SwiftUI
import SwiftData
import UserNotifications

@main
struct Did_I_Feed_The_Dog_App: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([Pet.self, FeedingEvent.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitContainerIdentifier: "iCloud.com.delon.DidIFeedTheDog"
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            container.mainContext.autosaveEnabled = true
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .task {
            await NotificationManager.shared.requestAuthorization()
        }
    }
}
