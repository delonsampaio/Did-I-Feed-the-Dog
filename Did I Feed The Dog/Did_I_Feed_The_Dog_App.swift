import SwiftUI
import SwiftData
import StoreKit

// File-scope so AppIntents (IntentDataAccess) reference the same container
// instance. Two CloudKit-enabled containers against the same store in one
// process cause "BUG IN CLIENT OF CLOUDKIT: Registering a handler for a
// CKScheduler activity identifier that has already been registered" and
// breaks sync.
let sharedModelContainer: ModelContainer = {
    let schema = Schema([Pet.self, FeedingEvent.self])
    let config = ModelConfiguration(
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

@main
struct Did_I_Feed_The_Dog_App: App {
    @UIApplicationDelegateAdaptor(QuickActionAppDelegate.self) var appDelegate
    @State private var deepLinkPetId: UUID? = nil
    private let entitlements = EntitlementManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkPetId: $deepLinkPetId)
                .onOpenURL { url in
                    deepLinkPetId = parseDeepLink(url)
                }
                .environment(entitlements)
                .task { await entitlements.initialize() }
        }
        .modelContainer(sharedModelContainer)
    }
}
