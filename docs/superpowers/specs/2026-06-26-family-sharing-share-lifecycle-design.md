# Family Sharing — Phase 3: Share Lifecycle (Backlog #57)

> Status: Design / awaiting review
> Date: 2026-06-26
> Depends on: Phase 1 Foundation + Phase 2 Sync Engine (both merged).
> Skill: `ios-cloudkit-custom-sharing` — `references/share-lifecycle.md`.

## Where this sits

Phase 1 built the shared Core Data store + UI seam. Phase 2 built the custom sync engine
(zone create, CD_ mapping, push/pull, echo suppression, safe tokens) talking to the
**sharedsync** container's `privateCloudDatabase` only — owner / same iCloud account.

Phase 3 makes sharing work **across different iCloud accounts**: create a zone-wide `CKShare`,
invite a participant, accept the invitation on the participant's device, and route every
CloudKit call to the correct database (owner → private, participant → shared). Plus owner
"stop sharing".

### Confirmed decisions (brainstorm 2026-06-26)

- **Scope = sharing mechanics only**, validated cross-account with a **DEBUG-seeded** SharedPet.
  No real-dog migration and no polished "Share" button this phase (those come with migration).
- **Lifecycle actions:** create + invite + accept + participant routing + **owner "stop sharing"**.
  Participant "leave" is deferred.
- **Still foreground/poll-driven** — no silent push this phase.
- **Read-write participants**, invite locked to `.allowReadWrite` (permission toggle hidden).
- **Pro-gated to invite** (decided Phase 1); accepting is free. (The DEBUG share trigger this
  phase is unguarded for testing; the real Pro gate lands with the polished Share button.)
- **Flag-gated** by `sharingFoundationEnabled` — dark in release, zero behavior change when off.

## The one architectural divergence from the skill

The skill accepts invitations with `NSPersistentCloudKitContainer.acceptShareInvitations(_:into:)`.
Our shared store is a **plain `NSPersistentContainer`** with a custom engine (no NSPCKC), so that
API is unavailable. Phase 3 accepts via **raw CloudKit** — `CKAcceptSharesOperation` on the
sharedsync container — then records the joined zone's scope and lets the existing pull engine
import the dog. Everything else follows the skill's share-lifecycle reference.

## Scope

### In scope

1. **`CloudKitIdentity`** — resolves and caches the current user's record name from the
   **sharedsync** `CKContainer` (`container.userRecordID()`). Identity differs per container
   (skill gotcha), so this must be seeded from the custom-sync container and used everywhere
   routing logic runs. Cached in memory + UserDefaults; refreshed on demand.

2. **`SyncStateStore`** (UserDefaults-backed) — per-zone metadata the engine needs to route:
   - `scope(forZone:) -> "private" | "shared"` / `setScope(_:forZone:)`
   - `ownerName(forZone:) -> String?` / `setOwnerName(_:forZone:)`
   - `allZones() -> [(zoneName, scope, ownerName)]` (so pull knows participant zones before the
     dog exists locally)
   - `removeZone(_:)` (stop-sharing / purge cleanup)
   Keys: `zoneScope.<zoneName>`, `zoneOwner.<zoneName>`.

3. **`SharedSyncEngine` generalization** (extends Phase 2, does not rewrite it):
   - `database(forZone:) -> CKDatabase` — owner zones → `privateCloudDatabase`, participant
     zones → `sharedCloudDatabase`. Decision rule (skill's seeding-window-safe heuristic):
     a zone is **owned/private** if `ownerName == CKCurrentUserDefaultName` OR
     `ownerName == cachedMyCloudKitID` OR a **private-scope token already exists** for it;
     otherwise **shared**. This is a pure function over (`zoneName`, `ownerName`, `myID`,
     `hasPrivateToken`) and is unit-tested.
   - `fetchAllZones()` now iterates **both** databases: `privateCloudDatabase` (owner zones)
     and `sharedCloudDatabase` (participant zones), each with its own scope-keyed DB token.
     `fetchZone` and `purgeZone` take the database + scope as parameters (Phase 2 hardcoded
     private). The token store already supports the `scope` key.
   - **Push routing**: `push(...)` groups records by their zone's database via `database(forZone:)`
     and issues `modifyRecords` per database. New zones default to owner/private (the seeded
     dog is owned by the sharer).

4. **`ShareController`** (owner side):
   - `makeShare(forRoot pet: SharedPet) async throws -> CKShare` — ensure the zone exists
     (reuse engine `ensureZone`), create a **zone-wide** `CKShare(recordZoneID:)`, set title +
     `publicPermission = .none`, save to `privateCloudDatabase`. Idempotent: on
     `serverRecordChanged`/`partialFailure`, fetch the existing well-known
     `CKRecordNameZoneWideShare` record and return it.
   - `fetchShare(forRoot:) async throws -> CKShare?` — for re-presenting the management UI.
   - `stopSharing(forRoot:) async` — `modifyRecordZones(deleting: [zoneID])` on
     `privateCloudDatabase`; locally purge the dog + tokens + sync state. Participants see
     `zoneNotFound` on their next pull → the Phase 2 purge path removes their copy.

5. **`CloudSharingView`** — `UICloudSharingController` wrapped in a `UIViewControllerRepresentable`,
   constructed with the saved `CKShare` and the **sharedsync** `CKContainer`,
   `availablePermissions = [.allowReadWrite, .allowPrivate]` (read-write only; no read-only
   toggle). Presented from the DEBUG "Share this dog" affordance.

6. **`ShareSceneDelegate` + AppDelegate hook** (participant side):
   - In the app delegate's `application(_:configurationForConnecting:options:)`, set
     `config.delegateClass = ShareSceneDelegate.self` **only when
     `options.cloudKitShareMetadata != nil`** (gotcha #5 — installing it unconditionally
     replaces SwiftUI's scene delegate and blanks cold launches).
   - `windowScene(_:userDidAcceptCloudKitShareWith metadata:)` runs a `CKAcceptSharesOperation`
     against the sharedsync container; on success records the zone in `SyncStateStore`
     (scope = "shared", ownerName from the metadata), posts `.didAcceptShare`, and triggers
     `SharedSyncEngine.fetchAllZones()` so the dog is pulled into the shared store.

7. **DEBUG affordances** (behind `sharingFoundationEnabled`, `#if DEBUG`):
   - On a shared-dog card / its detail: "Share this dog" → presents `CloudSharingView`;
     "Stop sharing" → `ShareController.stopSharing`.
   - These are temporary validation entry points; the real Pro-gated Share button ships with
     the migration phase.

### Out of scope (later phases)

- Silent push: `CKDatabaseSubscription`, `aps-environment`, `remote-notification` background
  mode, APNs (next phase).
- First-share migration (clone an owned `Pet` → `SharedPet`) and the polished, Pro-gated
  in-app Share entry point.
- Participant "leave share" (`CKShare` participant self-removal).
- Participant `loggedBy` attribution; `foodStockCount` counter-merge.
- Multi-participant management UI beyond what `UICloudSharingController` provides natively.

## Components & responsibilities

| Component | Responsibility | Depends on |
|---|---|---|
| `CloudKitIdentity` | Cache my user record name (sharedsync container) | CKContainer |
| `SyncStateStore` | Per-zone scope + owner persistence | UserDefaults |
| `SharedSyncEngine` (ext) | Route per zone; pull/push across both DBs | identity, state, token store, mapper |
| `ShareController` | Create/fetch share; stop sharing | engine, CKDatabase |
| `CloudSharingView` | Present `UICloudSharingController` | a saved `CKShare` |
| `ShareSceneDelegate` + AppDelegate hook | Accept invites; trigger pull | engine, SyncStateStore |
| DEBUG affordances | Trigger share / stop-sharing | ShareController, flag |

## Data flow (validation milestone — two DIFFERENT iCloud accounts)

1. **Owner** (account A, flag on): DEBUG-seed a SharedPet → tap "Share this dog" →
   `ShareController.makeShare` creates `Zone-<id>` + a zone-wide `CKShare` in A's private DB →
   `UICloudSharingController` sends an invite (Messages/link).
2. **Participant** (account B): taps the link → `ShareSceneDelegate` accepts via
   `CKAcceptSharesOperation` → records zone scope=shared/owner=A → `fetchAllZones()` pulls the
   zone from B's `sharedCloudDatabase` → the dog appears on B's dashboard (Phase 1 rendering).
3. **Edits** on either side route to the correct DB (`database(forZone:)`) and surface on the
   other side on the next foreground/poll fetch.
4. **Owner** taps "Stop sharing" → zone deleted from A's private DB → B's next pull gets
   `zoneNotFound` → B purges the local dog.

## Error handling

- **Flag off / engine not started:** no sharing code path runs; zero CloudKit calls.
- **Share already exists** (interrupted retry): fetch the well-known zone-wide share instead of
  failing.
- **Accept failure:** log; the participant can retry by re-opening the link. No partial local
  state is written until accept succeeds.
- **Routing during the owner seeding window:** the `hasPrivateToken` clause keeps a freshly
  created owned zone routing to the private DB even before `CloudKitIdentity` resolves
  (skill gotcha #4 window).
- **zoneNotFound on pull:** existing Phase 2 purge (now also clears `SyncStateStore`).
- Never `fatalError`. Cold launch must not break: the scene delegate is installed only for
  share-acceptance connections (gotcha #5).

## Testing

- **Unit:**
  - `database(forZone:)` routing decision — pure function over (ownerName, myID, hasPrivateToken)
    → private vs shared, including the seeding-window (`hasPrivateToken == true`) case and the
    `CKCurrentUserDefaultName`/`myID` cases.
  - `SyncStateStore` — scope/owner round-trip, `allZones()`, `removeZone`.
  - `CloudKitIdentity` cache read/write (mockable UserDefaults; the live `userRecordID()` fetch
    is not unit-tested).
- **Manual (two DIFFERENT iCloud accounts, real devices, DEBUG, flag on) — REQUIRED:**
  1. Owner shares a seeded dog → invite link delivered.
  2. Participant accepts → dog appears after a foreground fetch.
  3. Participant edits (DEBUG rename) → owner sees it; owner edits → participant sees it
     (routing both directions correct).
  4. Owner "Stop sharing" → dog disappears on the participant; no resurrection, no echo loop.
  5. Cold launch (no share link) still opens normally (scene-delegate guard holds).

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Accept can't use NSPCKC API | Use `CKAcceptSharesOperation` + manual scope record + engine pull |
| Scene delegate breaks cold launch (gotcha #5) | Install delegate class ONLY when `cloudKitShareMetadata != nil` |
| Wrong-DB routing (gotcha #4) | `database(forZone:)` rule incl. `hasPrivateToken` seeding-window guard; unit-tested |
| Identity differs per container | `CloudKitIdentity` seeded from the sharedsync container only |
| Pull misses participant zones | `fetchAllZones()` iterates both private and shared DBs with scope-keyed tokens |
| Regressing Phase 2 same-account sync | `database(forZone:)` returns private for owned zones; existing tests + same-account manual re-check |

## Done criteria for Phase 3

- App builds (app + widget); new unit tests pass; existing suite no new failures.
- Flag OFF: zero CloudKit calls, behavior identical to today.
- On two **different** iCloud accounts (flag on): a seeded dog shared from A is accepted on B
  and appears; edits round-trip both directions; owner stop-sharing purges B's copy; cold
  launch unaffected — confirmed by the manual checklist.
- Phase 2 same-account sync still works (no routing regression).
- Routing + state components are isolated, unit-tested units.
