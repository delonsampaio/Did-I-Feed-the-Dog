# Family Sharing — Phase 2: Sync Engine (Backlog #57)

> Status: Design / awaiting review
> Date: 2026-06-23
> Depends on: Phase 1 Foundation (`docs/superpowers/specs/2026-06-22-family-sharing-foundation-design.md`) — merged.
> Skill: `ios-cloudkit-custom-sharing` (Path A). This spec instantiates its mapping/pull/push references for this app.

## Where this sits

Phase 1 built the foundation: a separate Core Data store for shared dogs (`SharedDataStack` +
`SharedPet`/`SharedFeedingEvent`/`SharedMedication`/`SharedMedicationLog` with `ck*`
bookkeeping fields), a `DogDisplayable` seam, read-only dashboard rendering, all behind the
`sharingFoundationEnabled` flag. **No CloudKit traffic exists yet.**

Phase 2 makes that store actually sync: a custom CloudKit engine that mirrors the shared store
to/from the **separate** container `iCloud.com.delon.DidIFeedTheDog.sharedsync` (reserved in
Phase 1, still unused in code). The double isolation — separate container + plain
`NSPersistentContainer` (no NSPCKC) — is the structural defense against gotcha #7 (NSPCKC
adopting and deleting a custom zone).

### Confirmed decisions (brainstorm 2026-06-23)

- **Validation milestone:** sync a `SharedPet` (and its children) between two devices on the
  **same iCloud account**. Cross-account sharing (CKShare, invite/accept) is Phase 3.
- **Owner / private database only.** Every zone this phase is owned by the current user and
  lives in the sharedsync container's `privateCloudDatabase`. No `sharedCloudDatabase`
  routing, no participant logic.
- **No silent push this phase.** Sync is driven on app launch, on foreground (`scenePhase`
  active), and by a lightweight foreground poll. APNs / `aps-environment` entitlement /
  `remote-notification` background mode / `CKDatabaseSubscription` are deferred to Phase 3
  (where they pair with the sharing/accept flow). For a feeding app (open → log → close),
  launch+foreground fetch already makes the app current on open.
- **Conflict resolution: last-writer-wins (client-trumps).** On `.serverRecordChanged`,
  re-apply the local object's fields onto `ck.serverRecord` and retry once.
- **Gated by `sharingFoundationEnabled`.** The engine only runs when the flag is on, so the
  shipping app (flag off) is byte-identical to today and makes zero CloudKit calls.

## Scope

### In scope

1. **`CKRecordMapper`** — pure conversion between the shared store's `NSManagedObject`s and
   `CKRecord`s, using NSPCKC's `CD_` wire convention.
   - `ckRecord(for:) -> CKRecord?` — new vs existing (reuse `ckSystemFields` identity + change tag).
   - `applyFields(of:to:)` — `CD_<attr>` for attributes (Bool→1/0, UUID→`uuidString`,
     `Data`(`photoData`)→`CKAsset` via temp file), `CD_<rel>` = parent's `ckRecordName` string
     for each to-one relationship, plus `CD_entityName`. `skipped` excludes only the four `ck*`
     bookkeeping fields (`ckRecordName`, `ckSystemFields`, `ckZoneName`, `ckDatabaseScope`).
     All domain attributes — including the denormalized `lastFeedingDate`/`todaysFeedingCountRaw`
     — round-trip as plain `CD_` fields (see "Denormalized fields" below).
   - `encodedSystemFields(of:)` / `record(fromSystemFields:)`.
   - **Zone resolution** `zoneID(forNewObject:) -> CKRecordZone.ID?`:
     - Root `SharedPet` → `CKRecordZone.ID(zoneName: "Zone-\(pet.id.uuidString)", ownerName: CKCurrentUserDefaultName)`.
     - Any child → recurse up its to-one relationships (cycle-guarded by visited `objectID`s)
       to a synced ancestor's `ckSystemFields` zone, or to the root `SharedPet` base case.
   - **Upsert** `apply(records:deletions:into:)` — batch-fetch locals by `ckRecordName IN names`
     (one fetch per entity type), insert-or-update attributes, store `ckSystemFields`/`ckZoneName`/
     `ckDatabaseScope`, wire `CD_<rel>` strings to local objects in a second pass (fetch
     fallback for parents outside the batch), `context.assign(_, to: sharedStore)` every insert,
     apply deletions by `ckRecordName`.
   - Parent-before-child **rank** for push ordering: `SharedPet`(0) < `SharedFeedingEvent`/
     `SharedMedication`(1) < `SharedMedicationLog`(2).

2. **`SyncTokenStore`** — UserDefaults-backed change tokens.
   - DB change token; per-zone change token keyed `"zoneToken.<zoneName>.<scope>"` (scope =
     "private" this phase).
   - Archive-failure guard: if `NSKeyedArchiver` fails, **keep** the existing token — never fall
     through to `set(nil)` (which deletes the key → full zone re-download → re-push storm).
   - `moreComing`: callers persist only the **final** page's checkpoint.

3. **`SharedSyncEngine`** — `@MainActor` singleton; owns `CKContainer(identifier: "iCloud.com.delon.DidIFeedTheDog.sharedsync")`
   and its `privateCloudDatabase`.
   - **`ensureZone(forRoot pet:)`** — create `Zone-<pet.id>` via `modifyRecordZones(saving:)`
     if not already created (idempotent; tracked locally). No CKShare.
   - **Push** `push(saveObjectIDs:delete:)`:
     - Resolve objects, sort by rank (parents first), ensure each involved root pet's zone
       exists, build `CKRecord`s (`ckRecordName` minted for new objects).
     - `modifyRecords(saving:deleting:savePolicy: .ifServerRecordUnchanged, atomically: false)`.
     - On success: `writeBack` saved `ckSystemFields`/`ckRecordName` to the local object.
     - On `.serverRecordChanged`: re-apply local fields onto `ck.serverRecord`, collect, retry
       once (last-writer-wins).
     - Final bookkeeping `viewContext.save()` wrapped in `suppressingPush`.
   - **Pull** `fetchAllZones()`:
     - `databaseChanges(since:)` → save DB token; purge zones reported deleted; for each
       modified zone, `fetchZone` paged until `!moreComing`, applying each page on a background
       context, persisting only the final token; skip the `CKShare` system record.
     - Coalesce concurrent calls (`isSyncing` + `pendingFetch`); post one
       `.sharedRemoteChangeApplied` notification after all zones.
     - `CKError.zoneNotFound` → purge local zone data + tokens.
   - **Echo suppression:**
     - `applyingRemote` flag set around every remote-apply and bookkeeping save.
     - Push observer registered **synchronously** (`queue: nil`) on `SharedDataStack.viewContext`;
       skips when `applyingRemote`; filters inserted/updated shared-store objects → push;
       deletions resolved from stored system fields.
     - `pendingRemoteDeleteIDs: Set<String>` — record names received as remote deletions;
       push observer consume-and-skips them so the async deletion echo (promoted via
       `automaticallyMergesChangesFromParent`) never re-pushes a remote delete.
     - Log every deletion the push observer actually decides to send.

4. **Wiring & lifecycle.**
   - `SharedSyncEngine.shared.start()` is called once when `sharingFoundationEnabled` is on:
     attaches the push observer and runs an initial `fetchAllZones()`.
   - `fetchAllZones()` also runs on `scenePhase` → `.active` and on a lightweight foreground
     poll (e.g. a timer cancelled on background).
   - `SharedDogStore` already refreshes on the shared context's `DidSave` (Phase 1) and will
     also observe `.sharedRemoteChangeApplied` so pulled changes surface on the dashboard.

### Denormalized fields (decision)

`SharedPet.lastFeedingDate` and `todaysFeedingCountRaw` are denormalized caches (mirroring the
SwiftData `Pet`). They are **synced as plain fields** (simplest, consistent with NSPCKC's own
behavior of syncing all attributes) — last-writer-wins like any other field. They are not
recomputed on the receiving side in Phase 2. This is acceptable because Phase 2 has no logging
*into* shared dogs (that arrives later); the only writer is the DEBUG seeder. Revisit when
shared-dog logging lands.

### Explicitly out of scope (later phases)

- CKShare creation, zone-wide sharing, `UICloudSharingController` (Phase 3).
- Invite acceptance, `ShareSceneDelegate`, participant `sharedCloudDatabase` routing, "my
  CloudKit ID" seeding (Phase 3).
- Silent push: `CKDatabaseSubscription`, `aps-environment` entitlement, `remote-notification`
  background mode, APNs registration/handling (Phase 3).
- First-share migration cloning an owned `Pet` graph into the shared store (Phase 4) — in
  Phase 2 the only `SharedPet`s come from the Phase 1 DEBUG seeder.
- `foodStockCount` counter-merge (Phase 5 polish).
- Logging/editing *into* shared dogs from the UI (later phase).

## Architecture diagram

```
                 sharingFoundationEnabled == true
SharedDataStack.viewContext
   │  local save (seed / future edit)
   ▼
push observer (synchronous, queue: nil)         CKContainer("….sharedsync").privateCloudDatabase
   │  skip if applyingRemote / pendingRemoteDelete       ▲                         │
   ▼                                                     │ modifyRecords           │ recordZoneChanges
SharedSyncEngine.push ── ensureZone ─ rank ─ map ────────┘                         │
   ▲                                                                               ▼
   └── writeBack ckSystemFields (suppressed save)            SharedSyncEngine.fetchAllZones
                                                              │ background-context upsert
SharedDogStore ◀── .sharedRemoteChangeApplied ◀──────────────┘  (launch / foreground / poll)
   │
   ▼  dashboard (Phase 1 rendering, read-only shared cards)
```

## Components & responsibilities

| Component | Responsibility | Depends on |
|---|---|---|
| `CKRecordMapper` | Core Data ↔ CKRecord (CD_), zone resolution, upsert | Shared* entities |
| `SyncTokenStore` | Persist DB + per-zone change tokens safely | UserDefaults |
| `SharedSyncEngine` | Orchestrate zone create / push / pull / echo suppression | Mapper, TokenStore, SharedDataStack, CKContainer |
| App/Dashboard wiring | Start engine + drive fetch on launch/foreground/poll (flag-gated) | SharedSyncEngine, SharingFeatureFlag |

## Error handling

- **No store / flag off:** engine never starts; zero CloudKit calls; app identical to today.
- **CloudKit errors:** `zoneNotFound` → purge local zone + tokens. `serverRecordChanged` →
  LWW retry. Partial-batch failures (`atomically: false`) handled per-record; a single bad
  record never fails the batch. Network/other errors are logged; the next launch/foreground/
  poll retries (tokens make it resumable).
- **Token archive failure:** keep existing token, log — never erase.
- **Echo loops:** prevented by `applyingRemote` (synchronous observer) + `pendingRemoteDeleteIDs`.
- The engine never `fatalError`s.

## Testing

- **Unit (`CKRecordMapper`):** round-trip an object → `CKRecord` → upsert into a fresh
  in-memory context and assert field equality; `CD_` naming; Bool→1/0, UUID→string,
  `photoData`→`CKAsset`; `CD_entityName`; to-one `CD_<rel>` = parent `ckRecordName`; root zone
  = `Zone-<pet.id>`; child zone resolves via recursion (incl. new-parent-in-same-batch);
  rank ordering parents<children; upsert insert vs update by `ckRecordName`; deletion by name.
- **Unit (`SyncTokenStore`):** save/load round-trip; archive-failure keeps existing token;
  `set(nil)` never used; only final `moreComing` checkpoint persisted.
- **Unit (engine seams):** pure helpers extracted and tested — `rank(_:)`, `zoneID(forRoot:)`,
  the `applyingRemote`/`pendingRemoteDeleteIDs` decision logic (given inserted/updated/deleted
  sets + flags, decide what to push). Exclude live `CKDatabase` I/O.
- **Manual (device, DEBUG) — required:** per the skill's gotcha #6, validate live sync detached
  from Xcode on **two devices, same iCloud account, clean install, flag on**:
  1. Device A seeds a `SharedPet` → appears on Device B within a foreground fetch.
  2. Edit on A (e.g. rename via a temporary DEBUG action) → B reflects it.
  3. Delete on A → B removes it; no "resurrection" (deletion echo suppressed).
  4. No infinite loop / no duplicate records (echo suppression holds).
  The spec acknowledges the push/pull/echo paths are **not** unit-testable without a CloudKit
  mock; they are gated by manual device validation.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Echo loop (pull→push→pull) | Synchronous observer + `applyingRemote`; async deletion echo via `pendingRemoteDeleteIDs`; per-send deletion logging |
| Token loss → full re-download → re-push storm | Archive guard (never `set(nil)`); persist only final `moreComing` checkpoint |
| New child of new parent silently never syncs (gotcha #3) | Recursive cycle-guarded zone resolution to a synced ancestor / root base case |
| Cross-store graph (134060) | All shared inserts `context.assign(_, to: sharedStore)`; shared store is severed (no NSPCKC) |
| NSPCKC adopting the custom zone (gotcha #7) | Separate CloudKit container; shared store is a plain NSPersistentContainer |
| `photoData` CKAsset temp files leak | Write to temp file, delete after upload |
| Debugger masks push delivery (gotcha #6) | Manual validation run from home screen, not Xcode |

## Done criteria for Phase 2

- App builds (app + widget); all new unit tests pass; existing suite shows no new failures.
- With the flag OFF (release default): zero CloudKit calls; behavior identical to today.
- With the flag ON, on two same-account devices (clean install): a seeded `SharedPet` and its
  edits/deletes round-trip within a foreground fetch, with no echo loops, no duplicates, and no
  deletion resurrection — confirmed by the manual checklist above.
- The engine, mapper, and token store are isolated, file-focused units with unit tests for all
  non-CloudKit-I/O logic.
