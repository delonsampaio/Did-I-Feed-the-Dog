import CoreData
import Foundation

/// Fetches and observes shared dogs for the dashboard. Read-only surface in Phase 1
/// (no logging into shared dogs yet). On store-load failure it simply yields no dogs.
@Observable
@MainActor
final class SharedDogStore {

    private let stack: SharedDataStack
    // Holds the NotificationCenter observer token. Boxed so deinit (nonisolated)
    // can read it without crossing main-actor isolation; access is single-writer
    // (startObserving, on main) / single-reader (deinit), so @unchecked is safe.
    private final class ObserverBox: @unchecked Sendable {
        // nonisolated(unsafe): written once on main actor (startObserving),
        // read once in deinit (nonisolated). @unchecked Sendable documents
        // that we own the thread-safety contract.
        nonisolated(unsafe) var token: NSObjectProtocol?
    }
    private let observerBox = ObserverBox()
    private(set) var sharedPets: [SharedPet] = []

    init(stack: SharedDataStack) {
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
        observerBox.token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: stack.viewContext,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let token = observerBox.token { NotificationCenter.default.removeObserver(token) }
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
