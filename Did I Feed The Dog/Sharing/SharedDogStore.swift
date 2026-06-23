import CoreData
import Foundation

/// Fetches and observes shared dogs for the dashboard. Read-only surface in Phase 1
/// (no logging into shared dogs yet). On store-load failure it simply yields no dogs.
@Observable
@MainActor
final class SharedDogStore {

    private let stack: SharedDataStack
    // nonisolated(unsafe): written only from startObserving() (always on main),
    // read only from deinit (single-owner teardown). Safe — no concurrent access.
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    private(set) var sharedPets: [SharedPet] = []

    init(stack: SharedDataStack = .shared) {
        self.stack = stack
    }

    func refresh() {
        guard stack.loadError == nil else { sharedPets = []; return }
        let req = NSFetchRequest<SharedPet>(entityName: "SharedPet")
        req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        sharedPets = (try? stack.viewContext.fetch(req)) ?? []
    }

    func startObserving() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: stack.viewContext,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    #if DEBUG
    /// Inserts a fake shared dog so the foundation can be validated without CloudKit.
    func insertSampleDog(named name: String) {
        let p = SharedPet(context: stack.viewContext)
        p.id = UUID()
        p.name = name
        p.ckDatabaseScope = 1 // pretend it's a participant store record
        try? stack.viewContext.save()
        refresh()
    }
    #endif
}
