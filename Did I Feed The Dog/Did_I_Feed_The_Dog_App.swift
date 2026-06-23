import SwiftUI
import SwiftData
import StoreKit

// File-scope so AppIntents (IntentDataAccess) reference the same container
// instance. Two CloudKit-enabled containers against the same store in one
// process cause "BUG IN CLIENT OF CLOUDKIT: Registering a handler for a
// CKScheduler activity identifier that has already been registered" and
// breaks sync.
let sharedModelContainer: ModelContainer = {
    let schema = Schema([Pet.self, FeedingEvent.self, Medication.self, MedicationLog.self])
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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Migrate existing users: populate denormalized fields on first launch after update
        migrateDenormalizedFieldsIfNeeded()
        migrateMedLogPetIdsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(deepLinkPetId: $deepLinkPetId)
                .onOpenURL { url in
                    deepLinkPetId = parseDeepLink(url)
                }
                .environment(entitlements)
                .task {
                    await entitlements.initialize()
                    if SharingFeatureFlag.isFoundationEnabled { SharedSyncEngine.shared.start() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, SharingFeatureFlag.isFoundationEnabled {
                        Task { await SharedSyncEngine.shared.fetchAllZones() }
                    }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active, SharingFeatureFlag.isFoundationEnabled else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(20))
                        if Task.isCancelled { break }
                        await SharedSyncEngine.shared.fetchAllZones()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func migrateMedLogPetIdsIfNeeded() {
        let migrationKey = "didMigrateMedLogPetIds_v1"
        guard !UserDefaults.sharedGroup.bool(forKey: migrationKey) else { return }

        let context = sharedModelContainer.mainContext
        do {
            let logs = try context.fetch(FetchDescriptor<MedicationLog>())
            for log in logs where log.petId == nil {
                log.petId = log.medication?.pet?.id
            }
            try context.save()
            UserDefaults.sharedGroup.set(true, forKey: migrationKey)
        } catch {
            print("MedLog petId migration failed: \(error)")
        }
    }

    private func migrateDenormalizedFieldsIfNeeded() {
        let migrationKey = "didMigrateDenormalizedFields_v1"
        guard !UserDefaults.sharedGroup.bool(forKey: migrationKey) else { return }

        let context = sharedModelContainer.mainContext
        do {
            let pets = try context.fetch(FetchDescriptor<Pet>())
            for pet in pets {
                // Populate lastFeedingDate from relationship if not already set
                if pet.lastFeedingDate == nil, let lastEvent = pet.lastFeedingEvent {
                    pet.lastFeedingDate = lastEvent.timestamp
                }
                // Populate todaysFeedingCount
                let startOfDay = Calendar.current.startOfDay(for: .now)
                pet.todaysFeedingCount = (pet.feedingEvents ?? []).filter { $0.timestamp >= startOfDay }.count
            }
            try context.save()
            UserDefaults.sharedGroup.set(true, forKey: migrationKey)
        } catch {
            print("Migration failed: \(error)")
        }
    }
}
