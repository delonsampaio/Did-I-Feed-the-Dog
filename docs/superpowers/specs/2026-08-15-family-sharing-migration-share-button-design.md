# Family Sharing — Phase 5: Migration + Share Button (Backlog #57)

> Status: Design / awaiting review
> Date: 2026-08-15
> Depends on: Phases 1–4 (foundation, sync engine, share lifecycle mechanics, silent push) — all merged.
> Skill: `ios-cloudkit-custom-sharing`.

## Where this sits

Phases 1–4 built the parallel Core Data + CloudKit "sharedsync" stack, the custom sync engine
(push/pull, echo suppression, routing), and cross-account share lifecycle mechanics — but only
for **DEBUG-seeded** `SharedPet`s created directly in the shared store. There is still no path
from a real, owned SwiftData `Pet` into the shared store, and the only "Share"/"Stop sharing"
entry points are an unguarded `#if DEBUG` context menu on `SharedPetCard`.

Phase 5 closes that gap: **first-share migration** (clone an owned `Pet` → `SharedPet` the first
time a user shares a dog, and clone back on stop-sharing) plus the **real, Pro-gated Share
button** that replaces the DEBUG affordances. This is the last piece needed for a real user to
share a real dog with real history.

### Confirmed decisions (brainstorm 2026-08-14/15)

- **Migration replaces, not duplicates.** Sharing a dog clones its full graph (Pet + all
  FeedingEvents + Medications + MedicationLogs) into the shared store, then **deletes the owned
  copy**. The `SharedPet` becomes the single source of truth going forward — no two-way sync
  between SwiftData and the Core Data shared store to maintain.
- **Stop sharing reverse-migrates.** Owner-initiated "Stop sharing" clones the `SharedPet`'s
  current data back into a **new owned `Pet`**, then deletes the `SharedPet` + CloudKit zone.
  The owner never loses data by unsharing. Participants lose their copy via the existing
  `zoneNotFound` purge path (Phase 3, unchanged).
- **Entry point: context menu only.** "Share this dog" joins `PetCard`'s existing long-press
  context menu (alongside "Edit Dog"), matching the DEBUG pattern's discoverability level.
  Visible/persistent share affordances are a possible future polish, not this phase.
- **Identity preserved across migration.** The cloned object reuses the **same `id`** in both
  directions — the CloudKit zone name is derived from it (`"Zone-\(pet.id)"`), and dashboard
  code keys `ForEach` off `id`.
- **Ownership gating is new, required work.** Today any `SharedPet`, owned or received, shows
  the same DEBUG Share/Stop-sharing menu. The real button must show these only to the zone's
  **owner** — participants get neither.
- **Flag-gated** by `SharingFeatureFlag.isFoundationEnabled` — unchanged, dark in release until
  the flag flips on.

## Key existing-code constraints this design must respect

1. **The push observer only watches `SharedDataStack.shared.viewContext`** for
   `.NSManagedObjectContextDidSave`, and only forwards objects whose `ckRecordName` is already
   set at save time (`SharedSyncEngine.attachPushObserver`, reading
   `value(forKey: "ckRecordName")`). Migration code must (a) create new objects on `viewContext`,
   not a background context, and (b) explicitly stamp `ckRecordName = UUID().uuidString` on every
   new object before saving — cloning fields alone is not enough to trigger a push.
2. **No manual `ensureZone`/`push` call is needed.** `SharedSyncEngine.push(...)` already
   ensures a zone for any root `SharedPet` with `ckSystemFields == nil` (true for a freshly
   migrated pet) and pushes in rank order (`SharedPet` → `SharedFeedingEvent`/`SharedMedication`
   → `SharedMedicationLog`). Migration only needs to save; the existing observer does the rest.
3. **`ShareController.makeShare` is already idempotent** (fetches the well-known zone-wide share
   if one exists instead of failing) — safe to let the user retry "Share" after a transient
   failure without special-casing it in migration.
4. **Ownership signal already exists, just not exposed.** `database(forZone:)` treats a zone as
   owned if a **private-scope** zone token exists for it (`SyncTokenStore.loadZoneToken(_:scope:
   "private")`), among other checks. A participant's zone is fetched via the shared DB and gets a
   **shared-scope** token instead. This is a reliable, already-computed "do I own this zone"
   signal — Phase 5 exposes it, doesn't reinvent it.

## Scope

### In scope

1. **`SharePreparationController`** (new, `@MainActor enum`, mirrors `ShareController`'s style):
   - `migrateToShared(pet: Pet, context: ModelContext) throws -> SharedPet` — inserts a
     `SharedPet` into `SharedDataStack.shared.viewContext` reusing `pet.id`; clones every stored
     field 1:1 (`Int` fields widen to `Int64`; `feedingScheduleTimesRaw`/`reminderMinutesRaw`
     copy verbatim as they're already string-encoded in both models). Walks
     `pet.feedingEvents` → `SharedFeedingEvent`, `pet.medications` → `SharedMedication`,
     `medication.logs` → `SharedMedicationLog`, preserving the relationship graph. Stamps a
     fresh `ckRecordName = UUID().uuidString` on every new object. Saves `viewContext`; if the
     save throws, rolls back the inserted objects and rethrows — the owned `Pet` is untouched on
     failure. Only on save success does the caller proceed to delete the owned `Pet` (SwiftData
     cascade removes its `FeedingEvent`s/`Medication`s/`MedicationLog`s).
   - `migrateToOwned(sharedPet: SharedPet, context: ModelContext) throws -> Pet` — the mirror:
     clones the current `SharedPet` graph into a new SwiftData `Pet` (same `id`), inserts into
     the SwiftData `context`, saves. On success, caller proceeds to
     `ShareController.stopSharing` (unchanged) to delete the `SharedPet` + CloudKit zone.
   - Field mapping table (exhaustive, both directions):

     | Pet | SharedPet | Notes |
     |---|---|---|
     | `id: UUID` | `id: UUID` | same value both directions |
     | `name: String?` | `name: String?` | |
     | `birthday: Date?` | `birthday: Date?` | |
     | `photoData: Data?` | `photoData: Data?` | |
     | `foodStockCount: Int` | `foodStockCount: Int64` | widen/narrow |
     | `feedingScheduleTimesRaw: String` | `feedingScheduleTimesRaw: String` | verbatim copy |
     | `isFasting: Bool` | `isFasting: Bool` | |
     | `notificationsMuted: Bool` | `notificationsMuted: Bool` | |
     | `lastFeedingDate: Date?` | `lastFeedingDate: Date?` | |
     | `todaysFeedingCount: Int` | `todaysFeedingCountRaw: Int64` | widen/narrow |

     | FeedingEvent | SharedFeedingEvent | Notes |
     |---|---|---|
     | `timestamp: Date` | `timestamp: Date` | |
     | `mealType: String?` | `mealType: String?` | |
     | `notes: String` | `notes: String` | |
     | `loggedBy: String?` | `loggedBy: String?` | |
     | `didDeductStock: Bool?` | `didDeductStock: NSNumber?` | |
     | `portionsDeducted: Int?` | `portionsDeducted: NSNumber?` | |

     | Medication | SharedMedication | Notes |
     |---|---|---|
     | `id: UUID` | `id: UUID` | same value both directions |
     | `name: String` | `name: String` | |
     | `dose: String` | `dose: String` | |
     | `frequencyHours: Int` | `frequencyHours: Int64` | widen/narrow |
     | `notificationsEnabled: Bool` | `notificationsEnabled: Bool` | |
     | `reminderMinutes: [Int]` (raw-string backed) | `reminderMinutesRaw: String` | verbatim copy of the raw string (both sides use the same comma-joined encoding — `SharedMedication.reminderMinutes` computed accessor exists for this) |
     | `lastGivenDate: Date?` | `lastGivenDate: Date?` | |

     | MedicationLog | SharedMedicationLog | Notes |
     |---|---|---|
     | `id: UUID` | `id: UUID` | same value both directions |
     | `timestamp: Date` | `timestamp: Date` | |
     | `notes: String` | `notes: String` | |
     | `loggedBy: String` | `loggedBy: String` | |
     | `medicationName: String` | `medicationName: String` | |
     | `petId: UUID?` | `petId: UUID?` | same pet id both directions |

2. **`SharedSyncEngine.isOwner(ofZoneNamed zoneName: String) -> Bool`** (new public method) —
   thin wrapper exposing the existing private-scope-token check
   (`tokens.loadZoneToken(zoneName, scope: "private") != nil`) already used internally by
   `database(forZone:)`. No new logic; just a public seam for UI ownership gating.

3. **`PetCard` context menu** — add "Share this dog" alongside the existing "Start/End Fasting"
   and "Edit Dog" entries:
   - Tap → `if !entitlements.isPro`: present `PaywallSheet` (same pattern as
     `AddEditPetSheet.swift:179-188`), do not migrate.
   - `if entitlements.isPro`: call `SharePreparationController.migrateToShared(pet:context:)`.
     On success, call `ShareController.makeShare(forRoot:)` with the returned `SharedPet`, then
     present `CloudSharingView` via `.sheet(item:)` with the resulting `CKShare`. On failure at
     either step, show a simple error alert (`Text` + OK), matching the app's existing
     non-`fatalError` error-handling style; log via the sharing subsystem's `Logger`.

4. **`SharedPetCard`** — delete the `#if DEBUG` block entirely. Replace with a real,
   always-compiled context menu, gated by `SharedSyncEngine.isOwner(ofZoneNamed:)`:
   - Owner: "Share this dog" (re-presents `CloudSharingView` via `ShareController.fetchShare`
     if a share already exists, else creates one — supports adding more participants later) and
     "Stop sharing" (destructive) → `SharePreparationController.migrateToOwned(sharedPet:
     context:)` then `ShareController.stopSharing(forRoot:)`. On migration failure, show an error
     alert and do **not** call `stopSharing` — the shared copy must survive a failed reverse
     migration so no data is lost.
   - Participant: no context menu items related to sharing (view-only, unchanged from Phase 1).
   - The `#if DEBUG` `CKShare: @retroactive Identifiable` extension moves out of the `#if DEBUG`
     block since `CloudSharingView`'s `.sheet(item:)` now needs it unconditionally.

### Out of scope (Phase 6)

- Logging feedings/medications *on* a shared dog. `SharedPetCard` remains view-only regardless of
  the CloudKit-level read-write permission already granted to participants — no shared-store
  logging UI exists yet in any phase, including this one.
- `loggedBy` attribution for participant-originated shared-store writes.
- `foodStockCount` counter-merge (concurrent decrements from two devices).
- Participant "leave share" (self-removal).
- Multi-participant management UI beyond what `UICloudSharingController` provides natively.
- A more discoverable (non-context-menu) Share entry point.

## Components & responsibilities

| Component | Responsibility | Depends on |
|---|---|---|
| `SharePreparationController` | Clone Pet↔SharedPet graphs, stamp `ckRecordName` on new shared objects | `SharedDataStack`, SwiftData `ModelContext` |
| `SharedSyncEngine.isOwner(ofZoneNamed:)` | Expose existing private-token ownership check | `SyncTokenStore` |
| `PetCard` | Pro-gated Share entry point for owned dogs | `SharePreparationController`, `ShareController`, `EntitlementManager`, `PaywallSheet` |
| `SharedPetCard` | Owner-gated Share/Stop-sharing entry points for shared dogs | `SharePreparationController`, `ShareController`, `SharedSyncEngine.isOwner` |

## Data flow

1. **Share:** Owner taps "Share this dog" on an owned `PetCard` → Pro check → `!isPro` shows
   `PaywallSheet` and stops. `isPro` → `migrateToShared` clones the full graph into the shared
   store with fresh `ckRecordName`s and saves `viewContext` → the existing push observer fires
   automatically, `SharedSyncEngine.push` ensures the zone and uploads every record → on
   migration success the original `Pet` is deleted → `ShareController.makeShare(forRoot:)`
   creates the zone-wide `CKShare` → `CloudSharingView` presents the invite sheet. The dashboard
   now renders this dog via `SharedPetCard` (existing owned+shared merge logic, Phase 1,
   unchanged).
2. **Accept (unchanged, Phase 3):** participant accepts → dog appears on their dashboard.
3. **Stop sharing:** Owner taps "Stop sharing" on a `SharedPetCard` they own →
   `migrateToOwned` clones the current graph back into a new owned `Pet` and saves SwiftData →
   on success, `ShareController.stopSharing` deletes the CloudKit zone and purges the local
   `SharedPet` (unchanged, Phase 3) → the dashboard now renders this dog via the regular
   `PetCard` again. Participants get `zoneNotFound` on their next fetch and purge locally
   (unchanged, Phase 3).
4. **Retry safety:** if `makeShare` fails after a successful `migrateToShared`, the dog is now a
   `SharedPet` visible only to the owner (not yet actually shared with anyone) — tapping "Share
   this dog" again on the now-`SharedPetCard` is safe, since `makeShare` fetches the existing
   well-known share instead of erroring on a duplicate.

## Error handling

- **Migration save failure (either direction):** roll back inserted objects, leave the source
  object untouched, surface a simple alert. Never `fatalError`. The user can retry.
- **`makeShare` failure after successful `migrateToShared`:** dog stays a `SharedPet` (owner-only,
  not yet shared) — self-heals on retry via `makeShare`'s existing idempotency.
- **`migrateToOwned` failure during Stop sharing:** do **not** proceed to `stopSharing` — the
  `SharedPet` and its CloudKit zone must survive so no data is lost. Surface an alert; the user
  can retry Stop sharing later.
- **Flag off:** `SharingFeatureFlag.isFoundationEnabled` unchanged — Share entry points are
  simply not shown (existing pattern from Phases 1–4), zero behavior change.
- **Non-owner attempting owner actions:** prevented at the UI layer by `isOwner(ofZoneNamed:)`
  gating — no server-side enforcement needed since CloudKit itself will reject a non-owner's
  `modifyRecordZones(deleting:)` regardless.

## Testing

- **Unit:**
  - `SharePreparationController.migrateToShared` — full field round-trip for a `Pet` with
    `FeedingEvent`s, `Medication`s, and `MedicationLog`s; asserts every field in the mapping
    tables above, asserts `id` is preserved, asserts every new shared object has a non-nil
    `ckRecordName` before save.
  - `SharePreparationController.migrateToOwned` — the mirror round-trip.
  - Rollback-on-failure: simulate a Core Data save failure (e.g. an in-memory store with an
    injected constraint violation) and assert the source object graph is untouched.
  - `SharedSyncEngine.isOwner(ofZoneNamed:)` — true when a private-scope token exists for the
    zone name, false otherwise (mockable `SyncTokenStore`).
  - Pro-gate branch in the `PetCard` Share action: `!isPro` → paywall shown, no migration call;
    `isPro` → migration called.
- **Manual (two accounts, real devices, Pro entitlement active, flag on) — REQUIRED:**
  1. Owner shares a real dog with existing feeding/medication history → dashboard shows it as a
     `SharedPetCard`; participant accepts and sees the same history.
  2. Owner taps "Stop sharing" → dog returns to owner's dashboard as a normal `PetCard` with all
     history intact; participant's copy disappears.
  3. Non-Pro account taps "Share this dog" → paywall shown, no migration occurs, dog stays owned.
  4. Participant's `SharedPetCard` context menu shows no Share/Stop-sharing entries.
  5. Re-share the same dog a second time after stop-sharing → works normally (fresh zone, fresh
     `ckRecordName`s).

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Migration loses data on partial failure | Save-then-delete-source ordering in both directions; never delete source until the clone is confirmed persisted locally |
| Large feeding/medication history makes migration slow | Expected data volumes are a single home pet's history (hundreds, not millions, of rows) — synchronous foreground migration is acceptable; no batching/background work needed this phase |
| Push observer misses newly migrated objects | Explicit `ckRecordName` stamping on every new object before save (root cause of the constraint, called out above) |
| Non-owner sees/uses Share or Stop-sharing controls | `isOwner(ofZoneNamed:)` gate reusing existing, already-correct ownership signal |
| Re-sharing after stop-sharing collides with the old zone name | Zone name is deterministic (`Zone-\(id)`) but the old zone was deleted server-side by `stopSharing`; CloudKit allows recreating a zone with a previously-deleted name; all record names are freshly generated (`ckRecordName` reset to nil on the new owned `Pet`, since SwiftData `Pet` has no such field) |

## Done criteria for Phase 5

- App builds (app + widget); new unit tests pass; existing suite shows no new failures.
- Flag OFF: no behavior change — no Share entry points differ from pre-Phase-5 (DEBUG affordances
  were already flag-gated).
- On two real accounts with an active Pro entitlement: sharing a real dog with history works
  end-to-end, migration preserves all fields, stop-sharing restores the owner's data losslessly,
  ownership gating hides Share/Stop-sharing from participants — confirmed by the manual checklist.
- Phases 1–4 behavior (sync, routing, silent push) unaffected — no changes to `SharedSyncEngine`'s
  push/pull internals, only a new public read-only method.
