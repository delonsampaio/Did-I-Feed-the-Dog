# Family Sharing — Phase 1: Foundation (Backlog #57)

> Status: Phase 1 implemented (2026-06-22) — foundation merged behind `sharingFoundationEnabled` flag (default off)
> Date: 2026-06-22
> Backlog item: #57 — Family sharing / multi-user (per-dog, near-real-time, Pro-gated, read-write)

## Why this is decomposed

Backlog #57 ("shared access across different iCloud accounts") is a multi-layer
architectural epic, not a single feature. CloudKit user-to-user sharing requires
the custom **"Path A" sync engine** (per the `ios-cloudkit-custom-sharing` skill)
because `NSPersistentCloudKitContainer`'s native sharing frequently won't export a
participant's edits until the device locks — unacceptable for a household app where
"did someone just feed the dog?" must feel live.

Confirmed product shape (decided during brainstorming 2026-06-22):

- **Per-dog sharing** — each `Pet` is a shared root; one CloudKit zone per shared dog.
- **Near-real-time** — seconds, foreground → custom Path A engine, not native NSPCKC sharing.
- **Pro-gated to invite** — inviting requires the existing $0.99 Pro IAP. Accepting an
  invite as a participant is free.
- **Read-write participants** — everyone in the household can log; invites are locked to
  `.readWrite` (the permission toggle in `UICloudSharingController` is hidden).

The work is split into five phases, each spec'd → planned → built → validated on its own:

1. **Foundation (this spec)** — parallel Core Data shared stack + separate CloudKit
   container + a `DogDisplayable` UI seam so the dashboard renders both owned and shared
   dogs. No CloudKit traffic yet.
2. Sync engine — record↔CKRecord mapping (`CD_` convention), pull (zone tokens), push
   (save observer, echo suppression).
3. Share lifecycle — zone + zone-wide `CKShare`, `UICloudSharingController`, accept via
   scene delegate, Pro-gate.
4. First-share migration — clone a SwiftData `Pet`'s graph into the shared store on first share.
5. Polish — participant `loggedBy` attribution, conflict resolution, stop-sharing,
   notifications/widgets for shared dogs.

This document specs **Phase 1 only**.

## The core constraint that shapes everything

The app's data layer is **SwiftData** (`@Model` Pet/FeedingEvent/Medication/MedicationLog,
one `ModelContainer` with `cloudKitDatabase: .automatic` syncing to the CloudKit *private*
database). CloudKit sharing and the Path A engine require raw **Core Data +
`NSPersistentCloudKitContainer`** primitives that SwiftData does not expose:

- `context.assign(object, to: store)` — per-instance store routing. SwiftData routes by
  *type*, not per instance, so the assign-to-shared-store discipline (the single most
  destructive bug class, error 134060) is not even expressible in SwiftData.
- Persistent-history-driven push, direct `CKShare`/`CKDatabase` access, `CKRecord` mapping.

**Therefore shared dogs cannot live in the SwiftData store.** Introducing Core Data for
shared data is unavoidable. Phase 1 establishes that Core Data layer *alongside* SwiftData,
leaving the shipping private-data path completely untouched.

## Chosen architecture: parallel Core Data stack (Approach A)

- The user's **own** dogs stay in SwiftData / NSPCKC private sync, **unchanged**.
- **Shared** dogs live in a **separate Core Data stack** — a plain `NSPersistentContainer`
  (no NSPCKC) with persistent history tracking ON, backed by its own SQLite file in the app
  group. The custom CloudKit engine (Phase 2) will mirror this store to/from a **separate
  CloudKit container**, `iCloud.com.delon.DidIFeedTheDog.sharedsync`.
- A `DogDisplayable` protocol lets the dashboard render owned (`Pet`) and shared
  (`SharedPet`) dogs through one code path.

Why a *plain* `NSPersistentContainer` (not NSPCKC) for the shared store: the shared store is
synced entirely by our own engine. Keeping NSPCKC out of the shared stack — combined with the
separate CloudKit container — gives **double isolation** against the most dangerous failure in
the sharing skill (gotcha #7: NSPCKC adopting and then deleting a custom zone). The two stacks
are physically walled off and can never see each other's zones.

```
┌─ SwiftData (unchanged) ──────────────┐   ┌─ Core Data SharedDataStack (new) ─────────┐
│ ModelContainer                        │   │ NSPersistentContainer (no CloudKit)        │
│  Pet, FeedingEvent,                   │   │  SharedPet, SharedFeedingEvent,            │
│  Medication, MedicationLog            │   │  SharedMedication, SharedMedicationLog      │
│ cloudKitDatabase: .automatic          │   │ + sync bookkeeping fields                   │
│  → NSPCKC → private DB                 │   │ + persistent history tracking ON            │
│  → iCloud.com.delon.DidIFeedTheDog     │   │ store file: app group                       │
└───────────────────────────────────────┘   │ (Phase 2 engine →                           │
                                             │  iCloud.com.delon.DidIFeedTheDog.sharedsync)│
                                             └─────────────────────────────────────────────┘
                 \                                          /
                  \      DogDisplayable protocol           /
                   └──────────► DashboardView ◄───────────┘
                               renders both kinds
```

## Naming note

"Shared" is already overloaded in this app — `sharedFoodStock`, `StockMode`,
`stockOutScopeIsShared` all refer to the **pooled food-stock** feature (one stock count
across multiple dogs), which is unrelated to user-to-user sharing. To avoid collision:

- Core Data entities use the `Shared*` prefix (`SharedPet`) — these *are* CloudKit-shared.
- User-facing copy says **"Shared dog"** / "Shared with you".
- The internal stack/service is `SharedDataStack` / `SharedDogStore` — never reuse the
  food-stock `shared*` identifiers.

## Phase 1 scope

### In scope

1. **Separate CloudKit container in entitlements.** Add
   `iCloud.com.delon.DidIFeedTheDog.sharedsync` to the app target's
   `com.apple.developer.icloud-container-identifiers` array. (No code uses it yet — Phase 2
   does. Adding it now keeps the entitlement/provisioning change isolated and reviewable.)
   Widget target is left out until Phase 5.

2. **`SharedDataModel.xcdatamodeld`** — a Core Data model mirroring the four SwiftData
   entities, plus sync bookkeeping. Entities and attributes:

   - **SharedPet**: `id: UUID`, `name: String?`, `birthday: Date?`, `photoData: Binary`,
     `foodStockCount: Int64`, `feedingScheduleTimesRaw: String`, `isFasting: Bool`,
     `notificationsMuted: Bool`, `lastFeedingDate: Date?`, `todaysFeedingCount: Int64`.
     Relationships: `feedingEvents` (to-many, cascade), `medications` (to-many, cascade).
   - **SharedFeedingEvent**: `timestamp: Date`, `mealType: String?`, `notes: String`,
     `loggedBy: String?`, `didDeductStock: Bool?`, `portionsDeducted: Int64?`.
     Relationship: `pet` (to-one, inverse of feedingEvents).
   - **SharedMedication**: `id: UUID`, `name: String`, `dose: String`,
     `frequencyHours: Int64`, `notificationsEnabled: Bool`, `reminderMinutesRaw: String`
     (comma-joined, mirroring the `[Int]` transform), `lastGivenDate: Date?`.
     Relationships: `pet` (to-one), `logs` (to-many, nullify).
   - **SharedMedicationLog**: `id: UUID`, `timestamp: Date`, `notes: String`,
     `loggedBy: String`, `medicationName: String`, `petId: UUID?`.
     Relationship: `medication` (to-one, inverse of logs).
   - **Sync bookkeeping (on every entity)**: `ckRecordName: String?`,
     `ckSystemFields: Binary?`, `ckZoneName: String?`, `ckDatabaseScope: Int16`
     (0 = private/owner, 1 = shared/participant). Phase 1 sets none of these (no engine);
     they exist so Phase 2 needs no model migration.

   Store options: `NSPersistentHistoryTrackingKey = true`,
   `NSPersistentStoreRemoteChangeNotificationPostOptionKey = true`. Store file lives in the
   app group container (`group.com.delon.DidIFeedTheDog`) so intents/widgets can reach it later.

3. **`SharedDataStack`** — an `@Observable` singleton wrapping the `NSPersistentContainer`:
   `viewContext` (main-queue, `automaticallyMergesChangesFromParent = true`) and a
   `newBackgroundContext()` helper. Loads the store from the app group URL. This is the only
   object that knows about the Core Data container.

4. **`DogDisplayable` protocol** — the read surface the dashboard/`PetCard` need, conformed
   by both `Pet` (SwiftData) and `SharedPet` (Core Data):

   ```
   protocol DogDisplayable: Identifiable {
       var id: UUID { get }
       var displayName: String { get }
       var photoData: Data? { get }
       var birthday: Date? { get }
       var isFasting: Bool { get }
       var notificationsMuted: Bool { get }
       var lastFeedingDate: Date? { get }
       var todaysFeedingCount: Int { get }
       var ageString: String { get }
       var isShared: Bool { get }      // false for Pet, true for SharedPet
   }
   ```

   `Pet` gets a conformance extension (`displayName = name ?? "Dog"`, `isShared = false`,
   reuse existing `ageString`). `SharedPet` gets the parallel computed properties. Logic that
   is identical for both (e.g. `ageString`) is factored into a free function or shared
   extension so it is not duplicated/drifting.

5. **Dashboard merge + shared affordance.** `DashboardView` keeps its
   `@Query(sort: \Pet.name) pets` and adds a fetch of `SharedPet`s from `SharedDataStack`
   (observed via the remote-change / context-did-save notification so it refreshes live).
   The two lists merge into `[any DogDisplayable]` sorted by name and render through
   `PetCard`. Shared dogs get a small visual marker (e.g. a `person.2` badge / tinted ring)
   so they're distinguishable. `PetCard` is generalized to accept `any DogDisplayable` for
   its **display** surface. For a shared dog (`isShared == true`), `PetCard`'s action
   affordances (Log Meal, +/- stock, quick-toggle) are **disabled/hidden** in Phase 1 — the
   card is view-only until logging-into-shared-dogs lands with the Phase 2 sync engine. Owned
   dogs keep their full typed action path unchanged.

6. **Feature flag.** A compile-time/`UserDefaults` flag (`sharingFoundationEnabled`, default
   off in release) gates the shared-dog fetch and rendering so Phase 1 can ship dark and be
   validated without exposing an unfinished feature.

7. **Validation harness (DEBUG only).** A debug affordance (hidden Settings row under
   `#if DEBUG`) that inserts a sample `SharedPet` into the shared store, so we can confirm:
   a shared dog appears on the dashboard with the shared marker, renders correctly through
   `PetCard`, and **persists across relaunches**. No CloudKit involved.

### Explicitly out of scope (later phases)

- Any CloudKit traffic, zones, `CKShare`, invites, accept flow (Phases 2–3).
- **Logging into a shared dog** (tapping Log Meal on a shared card). Phase 1 renders shared
  dogs read-only; routing `FeedingLogService` to the Core Data store comes with the sync
  engine (Phase 2) so local writes are immediately backed by real sync.
- `PetDetailView`, `AddEditPetSheet`, intents, and widgets reading shared dogs.
- Participant identity / `loggedBy` attribution (Phase 5).
- Migration of an existing `Pet` into the shared store (Phase 4).

## Components (each independently testable)

| Component | Responsibility | Depends on |
|---|---|---|
| `SharedDataModel.xcdatamodeld` | Core Data schema for shared dogs + sync bookkeeping | — |
| `SharedDataStack` | Owns the `NSPersistentContainer`, app-group store, contexts | the model |
| `SharedPet` (+ siblings) | `NSManagedObject` subclasses (or codegen) | the model |
| `DogDisplayable` | Read-surface abstraction over `Pet` and `SharedPet` | both model layers |
| `SharedDogStore` | Fetches/observes `SharedPet`s for the dashboard; insert-sample (DEBUG) | `SharedDataStack` |
| `DashboardView` change | Merge + render owned and shared dogs; shared marker | `DogDisplayable`, `SharedDogStore` |
| `PetCard` change | Render `any DogDisplayable` | `DogDisplayable` |

## Data flow (Phase 1)

1. App launch → `SharedDataStack` loads the Core Data store from the app group (creates it
   empty on first run). No network.
2. `DashboardView` appears → `@Query` yields owned `Pet`s; `SharedDogStore.fetch()` yields
   `SharedPet`s. Merge → `[any DogDisplayable]` sorted by name.
3. (DEBUG) Tester inserts a sample `SharedPet` → Core Data save posts
   `NSManagedObjectContextDidSave` / remote-change notification → `SharedDogStore` refreshes
   → dashboard shows the shared dog with its marker.
4. Relaunch → store reloads → shared dog still present (persistence proven).

## Error handling

- **Store load failure:** the shared stack must **never** `fatalError` (unlike the SwiftData
  container) — a failure to open the *shared* store must not take down the app's core
  private-data experience. On load failure, log via the project's logger, set
  `SharedDataStack.loadError`, and have `SharedDogStore.fetch()` return `[]`. The dashboard
  then simply shows owned dogs only.
- **Empty shared store:** normal first-run state → owned dogs only; no UI change.
- **Feature flag off:** shared fetch is skipped entirely; behavior is byte-identical to today.

## Testing

- **Unit:** `DogDisplayable` conformance for both `Pet` and `SharedPet` (name fallback,
  `isShared`, `ageString` parity); `reminderMinutesRaw` ↔ `[Int]` round-trip; `SharedDataStack`
  loads an in-memory store and round-trips a `SharedPet` insert/fetch.
- **Unit:** shared `ageString` logic produces identical output for an owned and a shared dog
  with the same birthday (guards against drift between the two model layers).
- **Manual (DEBUG harness):** insert sample shared dog → appears with marker → relaunch →
  persists. Toggle feature flag off → shared dog disappears, owned dogs unaffected.
- **Regression:** existing test suite passes unchanged (private path untouched). Build both
  app and widget targets (widget entitlement unchanged, must still compile).

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Two model layers drift (Pet vs SharedPet fields diverge) | Single source for shared logic (`ageString` etc.); parity unit test; field list mirrored in this spec |
| Separate CloudKit container needs provisioning profile regen | Entitlement change is isolated in Phase 1; flagged for the developer to update the App ID / profile before Phase 2 needs it |
| `PetCard` generalization regresses owned-dog rendering | `PetCard` keeps a typed path for actions (logging) that still takes `Pet`; only the display surface goes through `DogDisplayable` in Phase 1 |
| App-group store path mismatch with SwiftData group | Reuse the exact `group.com.delon.DidIFeedTheDog` identifier already in entitlements |

## Done criteria for Phase 1

- App builds (app + widget targets) and the existing test suite passes.
- With the feature flag ON in DEBUG, inserting a sample `SharedPet` shows it on the dashboard
  with a shared marker, rendered via `PetCard`, persisting across relaunch.
- With the flag OFF (release default), the app is behaviorally identical to today.
- No NSPCKC / SwiftData private-path code is modified beyond the additive dashboard merge.
- The `iCloud.com.delon.DidIFeedTheDog.sharedsync` container is present in entitlements,
  unused, ready for Phase 2.
