# Family Sharing — Phase 3 Share Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cross-account sharing for the shared store — create a zone-wide `CKShare`, invite a participant, accept on the participant's device via raw CloudKit, and route every sync call to the correct database (owner→private, participant→shared), plus owner "stop sharing" — validated with a DEBUG-seeded dog on two iCloud accounts.

**Architecture:** Extends the Phase 2 `SharedSyncEngine` (does not rewrite it). Adds `CloudKitIdentity` (my record name from the sharedsync container), a pure `isOwnedZone` routing decision + `database(forZone:)`, a two-database pull, per-zone push routing, a `ShareController` (create/fetch/stop share), a `CloudSharingView` (UICloudSharingController), and share-acceptance handling added to the **existing** `QuickActionSceneDelegate`. All behind `sharingFoundationEnabled`.

**Tech Stack:** Swift, CloudKit (`CKShare`, `CKAcceptSharesOperation`, `UICloudSharingController`, `databaseChanges`/`recordZoneChanges`/`modifyRecords`/`modifyRecordZones`), Core Data, XCTest.

## Global Constraints

- **Design source:** `docs/superpowers/specs/2026-06-26-family-sharing-share-lifecycle-design.md`.
- **Container:** `iCloud.com.delon.DidIFeedTheDog.sharedsync`. Owner zones live in its `privateCloudDatabase`; participant zones in its `sharedCloudDatabase`.
- **Flag-gated:** every new CloudKit entry point (`database(forZone:)` routing, two-DB pull, share create/accept/stop) runs only when `SharingFeatureFlag.isFoundationEnabled`. Flag off = zero CloudKit calls, behavior identical to today.
- **Accept via raw CloudKit:** the shared store is a plain `NSPersistentContainer` (no NSPCKC), so accept with `CKAcceptSharesOperation` on the sharedsync container — NOT `NSPersistentCloudKitContainer.acceptShareInvitations`.
- **Scene-delegate refinement (supersedes the spec's separate ShareSceneDelegate + conditional config):** the app already installs `QuickActionSceneDelegate` unconditionally (`QuickActionAppDelegate.application(_:configurationForConnecting:options:)`). Extend THAT delegate to also handle share acceptance (`windowScene(_:userDidAcceptCloudKitShareWith:)` and `connectionOptions.cloudKitShareMetadata` in `scene(_:willConnectTo:)`). Do NOT add a second scene delegate or touch `configurationForConnecting` — gotcha #5 is already neutralized because a custom delegate exists.
- **YAGNI (supersedes the spec's `SyncStateStore`):** per-database `databaseChanges` enumeration + the `isOwnedZone` heuristic fully cover routing; no separate per-zone scope store is needed this phase. (If a later phase needs persisted owner names — e.g. participant share management — add it then.)
- **Invite permissions:** lock `UICloudSharingController.availablePermissions = [.allowReadWrite, .allowPrivate]` (read-write only; no read-only or public toggle).
- **Read-write participants; Pro-gate deferred:** the DEBUG share trigger is unguarded this phase (the real Pro gate ships with the polished Share button).
- **Never `fatalError`.** Log via `os.Logger(subsystem: "com.delon.DidIFeedTheDog", category: ...)`.

### Environment / mechanics (every task)

- New files → `Did I Feed The Dog/Sharing/` or `Did I Feed The Dog/Views/` (target "Did I Feed The Dog"); tests → `Did I Feed The DogTests/` (target "Did I Feed The DogTests"). Xcode 16 filesystem-synchronized groups — **no `project.pbxproj` edits**.
- **Swift 6 `-default-isolation=MainActor` strict concurrency is enforced on the developer's toolchain.** Mark any `static let`/`static func` accessed from a `nonisolated` context (e.g. inside the synchronous save observer, or pure helpers) **`nonisolated`**. Pure static helpers (`isOwnedZone`, stores) should be `nonisolated`. The engine class stays `@MainActor`.
- **Single simulator (limited RAM — never spawn parallel clones).** Test:
  ```
  xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:"Did I Feed The DogTests/<ClassName>" 2>&1 | tail -40
  ```
  Build:
  ```
  xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
  ```
- **Known-flaky baseline:** two slow `FeedingLogServiceTests` (~100s, timeout-prone), a stale `PetTests.testAgeStringMonthsOnly`. Judge success by new tests passing + no NEW failures in touched files.
- Verify exact CloudKit async API shapes against the SDK (use the LSP tool); adapt labels minimally if the compiler disagrees, keeping behavior, and note it.

---

### Task 1: SyncTokenStore — per-scope DB token

**Files:**
- Modify: `Did I Feed The Dog/Sharing/SyncTokenStore.swift`
- Test: `Did I Feed The DogTests/SyncTokenStoreDBScopeTests.swift`

**Interfaces:**
- Produces: `func loadDBToken(scope: String) -> CKServerChangeToken?` and `func saveDBToken(_:scope:)` (key `"sharedSyncDBToken.<scope>"`). The old no-arg `loadDBToken()/saveDBToken(_:)` are replaced (Task 4 updates the one caller).

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/SyncTokenStoreDBScopeTests.swift`:

```swift
import XCTest
import CloudKit
@testable import Did_I_Feed_The_Dog

final class SyncTokenStoreDBScopeTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SyncTokenStoreDBScopeTests-\(UUID().uuidString)")!
    }

    func testDBTokenIsScoped() {
        let d = freshDefaults()
        let store = SyncTokenStore(defaults: d)
        XCTAssertNil(store.loadDBToken(scope: "private"))
        XCTAssertNil(store.loadDBToken(scope: "shared"))
        // A corrupt blob under the private DB key must not bleed into the shared scope.
        d.set(Data([0x00]), forKey: "sharedSyncDBToken.private")
        XCTAssertNil(store.loadDBToken(scope: "private")) // corrupt → nil, no crash
        XCTAssertNil(store.loadDBToken(scope: "shared"))  // different key
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/SyncTokenStoreDBScopeTests"`. Expected: compile failure (`loadDBToken(scope:)` not found).

- [ ] **Step 3: Implement**

In `Did I Feed The Dog/Sharing/SyncTokenStore.swift`, replace the DB-token section:

```swift
    // MARK: DB token (per database scope: "private" | "shared")
    private func dbKey(_ scope: String) -> String { "sharedSyncDBToken.\(scope)" }
    func loadDBToken(scope: String) -> CKServerChangeToken? { unarchive(defaults.data(forKey: dbKey(scope))) }
    func saveDBToken(_ token: CKServerChangeToken, scope: String) { archiveAndStore(token, key: dbKey(scope)) }
```

(Delete the old `private static let dbKey` line and the old no-arg `loadDBToken()/saveDBToken(_:)`.)

- [ ] **Step 4: Run test to verify it passes**

Run `-only-testing:"Did I Feed The DogTests/SyncTokenStoreDBScopeTests"`. Expected: PASS. (The existing `SyncTokenStoreTests` that referenced the old DB API, if any, are updated by their assertions on `sharedSyncDBToken.private` — the key is unchanged for the private scope, so they still pass. If a compile error references the old `loadDBToken()`, it is only called from `SharedSyncEngine` which Task 4 updates; this task's build is verified via the test target which does not require the app to call it.)

> Note: if the app target fails to compile because `SharedSyncEngine.fetchAllZones` still calls the old `loadDBToken()`, that is expected until Task 4. Run only the focused test class here; do not run a full app build in this task.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SyncTokenStore.swift" "Did I Feed The DogTests/SyncTokenStoreDBScopeTests.swift"
git commit -m "feat: per-scope DB change token in SyncTokenStore (#57 phase 3)"
```

---

### Task 2: CloudKitIdentity

**Files:**
- Create: `Did I Feed The Dog/Sharing/CloudKitIdentity.swift`
- Test: `Did I Feed The DogTests/CloudKitIdentityTests.swift`

**Interfaces:**
- Produces: `@MainActor final class CloudKitIdentity` with `static let shared`, `init(defaults:)`, `private(set) var cachedID: String?` (loaded from UserDefaults on init), `func refresh() async` (fetches `container.userRecordID()` and caches `.recordName`).

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/CloudKitIdentityTests.swift`:

```swift
import XCTest
@testable import Did_I_Feed_The_Dog

@MainActor
final class CloudKitIdentityTests: XCTestCase {
    func testLoadsCachedIDFromDefaultsOnInit() {
        let d = UserDefaults(suiteName: "CloudKitIdentityTests-\(UUID().uuidString)")!
        d.set("user-record-123", forKey: "sharedSyncMyCloudKitID")
        let identity = CloudKitIdentity(defaults: d)
        XCTAssertEqual(identity.cachedID, "user-record-123")
    }

    func testNilWhenNoCache() {
        let d = UserDefaults(suiteName: "CloudKitIdentityTests-\(UUID().uuidString)")!
        XCTAssertNil(CloudKitIdentity(defaults: d).cachedID)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/CloudKitIdentityTests"`. Expected: compile failure (`CloudKitIdentity` undefined).

- [ ] **Step 3: Implement**

Create `Did I Feed The Dog/Sharing/CloudKitIdentity.swift`:

```swift
import CloudKit
import Foundation
import os

/// Caches the current user's CloudKit record name FROM THE sharedsync CONTAINER.
/// Identity differs per container, so routing logic must use this value (seeded from the
/// custom-sync container), never the NSPCKC container's user ID.
@MainActor
final class CloudKitIdentity {
    static let shared = CloudKitIdentity()

    private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "CloudKitIdentity")
    private static let key = "sharedSyncMyCloudKitID"

    private let container = CKContainer(identifier: "iCloud.com.delon.DidIFeedTheDog.sharedsync")
    private let defaults: UserDefaults
    private(set) var cachedID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cachedID = defaults.string(forKey: Self.key)
    }

    /// Fetches and caches the user record name. Best-effort; failures keep the existing cache.
    func refresh() async {
        do {
            let id = try await container.userRecordID()
            cachedID = id.recordName
            defaults.set(id.recordName, forKey: Self.key)
        } catch {
            Self.log.error("userRecordID failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run `-only-testing:"Did I Feed The DogTests/CloudKitIdentityTests"`. Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/CloudKitIdentity.swift" "Did I Feed The DogTests/CloudKitIdentityTests.swift"
git commit -m "feat: CloudKitIdentity caches sharedsync user record name (#57 phase 3)"
```

---

### Task 3: Engine routing decision (`isOwnedZone` + `database(forZone:)`)

**Files:**
- Modify: `Did I Feed The Dog/Sharing/SharedSyncEngine.swift`
- Test: `Did I Feed The DogTests/SharedSyncEngineRoutingTests.swift`

**Interfaces:**
- Consumes: `CloudKitIdentity`, `SyncTokenStore`.
- Produces:
  - `nonisolated static func isOwnedZone(ownerName: String, myCloudKitID: String?, hasPrivateToken: Bool) -> Bool` — pure.
  - `private var sharedDB: CKDatabase { container.sharedCloudDatabase }`
  - `private func database(forZone zoneID: CKRecordZone.ID) -> CKDatabase`

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/SharedSyncEngineRoutingTests.swift`:

```swift
import XCTest
import CloudKit
@testable import Did_I_Feed_The_Dog

final class SharedSyncEngineRoutingTests: XCTestCase {
    func testCurrentUserSentinelIsOwned() {
        XCTAssertTrue(SharedSyncEngine.isOwnedZone(
            ownerName: CKCurrentUserDefaultName, myCloudKitID: "me", hasPrivateToken: false))
    }

    func testMyRealRecordNameIsOwned() {
        XCTAssertTrue(SharedSyncEngine.isOwnedZone(
            ownerName: "me", myCloudKitID: "me", hasPrivateToken: false))
    }

    func testPrivateTokenMeansOwnedEvenIfOwnerUnknown() {
        // Seeding window: owner created the zone, identity not yet resolved, but a private
        // token already exists → still owned.
        XCTAssertTrue(SharedSyncEngine.isOwnedZone(
            ownerName: "someone", myCloudKitID: nil, hasPrivateToken: true))
    }

    func testOtherOwnerWithNoPrivateTokenIsShared() {
        XCTAssertFalse(SharedSyncEngine.isOwnedZone(
            ownerName: "owner-A", myCloudKitID: "me", hasPrivateToken: false))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/SharedSyncEngineRoutingTests"`. Expected: compile failure (`isOwnedZone` undefined).

- [ ] **Step 3: Implement**

In `SharedSyncEngine.swift`, add `sharedDB` next to `privateDB`:

```swift
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
```

Add the routing members (place after `pushDecision`):

```swift
    /// Pure routing decision: is this zone owned by the current user (→ privateCloudDatabase)
    /// or shared with them (→ sharedCloudDatabase)? Owned if the owner is the current-user
    /// sentinel, or the cached own record name, or a private-scope token already exists
    /// (covers the owner's zone-creation seeding window before identity resolves).
    nonisolated static func isOwnedZone(ownerName: String, myCloudKitID: String?, hasPrivateToken: Bool) -> Bool {
        if ownerName == CKCurrentUserDefaultName { return true }
        if let myCloudKitID, ownerName == myCloudKitID { return true }
        return hasPrivateToken
    }

    private func database(forZone zoneID: CKRecordZone.ID) -> CKDatabase {
        let hasPriv = tokens.loadZoneToken(zoneID.zoneName, scope: "private") != nil
        let owned = Self.isOwnedZone(ownerName: zoneID.ownerName,
                                     myCloudKitID: CloudKitIdentity.shared.cachedID,
                                     hasPrivateToken: hasPriv)
        return owned ? privateDB : sharedDB
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run `-only-testing:"Did I Feed The DogTests/SharedSyncEngineRoutingTests"`. Expected: 4 PASS. (App may not fully build yet — Task 4/5 wire `database(forZone:)`/`sharedDB` into pull/push. The focused test only needs the static `isOwnedZone`, which compiles. If the app target fails because `database(forZone:)` is unused, add `_ = database(forZone:)` is NOT needed — an unused private method is only a warning; if it errors, proceed to Task 4 which uses it.)

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedSyncEngine.swift" "Did I Feed The DogTests/SharedSyncEngineRoutingTests.swift"
git commit -m "feat: zone→database routing decision in SharedSyncEngine (#57 phase 3)"
```

---

### Task 4: Engine pull across both databases

**Files:**
- Modify: `Did I Feed The Dog/Sharing/SharedSyncEngine.swift`

**Interfaces:**
- Consumes: Task 1 (`loadDBToken(scope:)`), Task 3 (`sharedDB`).
- Produces: `fetchAllZones()` iterates private + shared DBs; `fetchZone(_:in:scope:)` and `purgeZone(_:scope:)` are database/scope-parameterized.

- [ ] **Step 1: Replace `fetchAllZones`, `fetchZone`, `purgeZone`**

In `SharedSyncEngine.swift`, replace the three methods (current `fetchAllZones`, `fetchZone(_:)`, `purgeZone(_:)`) with:

```swift
    func fetchAllZones() async {
        guard SharingFeatureFlag.isFoundationEnabled else { return }
        guard !isSyncing else { pendingFetch = true; return }
        isSyncing = true; defer { isSyncing = false }
        repeat {
            pendingFetch = false
            var anyApplied = false
            anyApplied = await fetchDatabase(privateDB, scope: "private") || anyApplied
            anyApplied = await fetchDatabase(sharedDB, scope: "shared") || anyApplied
            if anyApplied {
                NotificationCenter.default.post(name: .sharedRemoteChangeApplied, object: nil)
            }
        } while pendingFetch
    }

    /// Fetch all changed zones for one database (owner=private / participant=shared).
    private func fetchDatabase(_ db: CKDatabase, scope: String) async -> Bool {
        do {
            let dbChanges = try await db.databaseChanges(since: tokens.loadDBToken(scope: scope))
            tokens.saveDBToken(dbChanges.changeToken, scope: scope)
            for deletion in dbChanges.deletions { purgeZone(deletion.zoneID, scope: scope) }
            var anyApplied = false
            for mod in dbChanges.modifications {
                let n = await fetchZone(mod.zoneID, in: db, scope: scope)
                anyApplied = anyApplied || (n > 0)
            }
            return anyApplied
        } catch {
            Self.log.error("fetchDatabase(\(scope, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func fetchZone(_ zoneID: CKRecordZone.ID, in db: CKDatabase, scope: String) async -> Int {
        var since = tokens.loadZoneToken(zoneID.zoneName, scope: scope)
        var checkpoint: CKServerChangeToken?
        var more = false
        var total = 0
        repeat {
            do {
                let changes = try await db.recordZoneChanges(inZoneWith: zoneID, since: since)
                let records = changes.modificationResultsByID.values
                    .compactMap { try? $0.get().record }
                    .filter { $0.recordType != CKRecord.SystemType.share }
                let deletions = changes.deletions.map(\.recordID)
                if !records.isEmpty || !deletions.isEmpty {
                    for id in deletions { SharedSyncEngine.pendingRemoteDeleteIDs.insert(id.recordName) }
                    let bg = stack.newBackgroundContext()
                    await bg.perform {
                        SharedSyncEngine.applyingRemote = true
                        CKRecordMapper.apply(records: records, deletions: deletions, into: bg)
                        try? bg.save()
                        SharedSyncEngine.applyingRemote = false
                    }
                    total += records.count + deletions.count
                }
                since = changes.changeToken
                checkpoint = changes.changeToken
                more = changes.moreComing
            } catch let e as CKError where e.code == .zoneNotFound {
                purgeZone(zoneID, scope: scope)
                return total
            } catch {
                Self.log.error("fetchZone \(zoneID.zoneName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return total
            }
        } while more
        if let checkpoint { tokens.saveZoneToken(checkpoint, zoneName: zoneID.zoneName, scope: scope) }
        return total
    }

    private func purgeZone(_ zoneID: CKRecordZone.ID, scope: String) {
        let bg = stack.newBackgroundContext()
        bg.perform {
            SharedSyncEngine.applyingRemote = true
            let req = NSFetchRequest<NSManagedObject>(entityName: "SharedPet")
            req.predicate = NSPredicate(format: "ckZoneName == %@", zoneID.zoneName)
            for pet in (try? bg.fetch(req)) ?? [] { bg.delete(pet) } // cascade removes children
            try? bg.save()
            SharedSyncEngine.applyingRemote = false
        }
        tokens.clearZoneTokens(zoneID.zoneName)
        createdZones.remove(zoneID.zoneName)
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run the app build. Expected: BUILD SUCCEEDED. (`database(forZone:)` from Task 3 is still only used by push, added in Task 5 — an unused private method is at most a warning. If the compiler errors on the unused method, proceed; Task 5 immediately uses it. If it errors on the OLD no-arg `loadDBToken()` anywhere, confirm this task removed the only caller — it did, in `fetchAllZones`.)

- [ ] **Step 3: Regression test**

Run `-only-testing:"Did I Feed The DogTests/SharedSyncEnginePushDecisionTests"`. Expected: 3 PASS.

- [ ] **Step 4: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedSyncEngine.swift"
git commit -m "feat: pull from both private and shared databases (#57 phase 3)"
```

---

### Task 5: Engine push routing per zone

**Files:**
- Modify: `Did I Feed The Dog/Sharing/SharedSyncEngine.swift` (the `push` method)

**Interfaces:**
- Consumes: `database(forZone:)` (Task 3).
- Produces: `push(...)` groups records + deletions by their zone's database and issues `modifyRecords` per database; write-back/conflict handling unchanged per group.

- [ ] **Step 1: Replace the `push` method body's modify section**

In `SharedSyncEngine.swift`, replace the `push(saveObjectIDs:delete:)` method with this version (it groups by database; the per-record success/conflict/write-back logic is unchanged, just executed per group):

```swift
    func push(saveObjectIDs: [NSManagedObjectID], delete recordIDs: [CKRecord.ID]) async {
        let ctx = stack.viewContext
        let objects = saveObjectIDs.compactMap { try? ctx.existingObject(with: $0) }
            .sorted { CKRecordMapper.rank(for: $0) < CKRecordMapper.rank(for: $1) }

        var rootsEnsured: Set<NSManagedObjectID> = []
        for obj in objects {
            if let root = rootPet(of: obj), !rootsEnsured.contains(root.objectID) {
                await ensureZone(forRoot: root)
                rootsEnsured.insert(root.objectID)
            }
        }

        var records: [CKRecord] = []
        var objectByName: [String: NSManagedObject] = [:]
        for obj in objects {
            if let r = CKRecordMapper.ckRecord(for: obj), let n = obj.value(forKey: "ckRecordName") as? String {
                records.append(r); objectByName[n] = obj
            }
        }
        guard !records.isEmpty || !recordIDs.isEmpty else { return }

        let tempAssetURLs: [URL] = records.flatMap { record in
            record.allKeys().compactMap { key -> URL? in
                guard let asset = record[key] as? CKAsset, let url = asset.fileURL else { return nil }
                return url.path.hasPrefix(FileManager.default.temporaryDirectory.path) ? url : nil
            }
        }

        // Group by destination database (owner→private, participant→shared).
        var saveByDB: [ObjectIdentifier: (db: CKDatabase, records: [CKRecord])] = [:]
        for r in records {
            let db = database(forZone: r.recordID.zoneID)
            saveByDB[ObjectIdentifier(db), default: (db, [])].records.append(r)
        }
        var deleteByDB: [ObjectIdentifier: (db: CKDatabase, ids: [CKRecord.ID])] = [:]
        for id in recordIDs {
            let db = database(forZone: id.zoneID)
            deleteByDB[ObjectIdentifier(db), default: (db, [])].ids.append(id)
        }
        let dbKeys = Set(saveByDB.keys).union(deleteByDB.keys)

        for key in dbKeys {
            let db = saveByDB[key]?.db ?? deleteByDB[key]!.db
            let saves = saveByDB[key]?.records ?? []
            let deletes = deleteByDB[key]?.ids ?? []
            await pushGroup(saving: saves, deleting: deletes, to: db, objectByName: objectByName, ctx: ctx)
        }

        for url in tempAssetURLs { try? FileManager.default.removeItem(at: url) }
    }

    /// Upload one database's worth of records with LWW conflict handling + write-back.
    private func pushGroup(saving records: [CKRecord], deleting recordIDs: [CKRecord.ID],
                           to db: CKDatabase, objectByName: [String: NSManagedObject],
                           ctx: NSManagedObjectContext) async {
        guard !records.isEmpty || !recordIDs.isEmpty else { return }
        do {
            let (saveResults, _) = try await db.modifyRecords(
                saving: records, deleting: recordIDs,
                savePolicy: .ifServerRecordUnchanged, atomically: false)
            var conflicts: [CKRecord] = []
            for (id, result) in saveResults {
                switch result {
                case .success(let saved):
                    if let obj = objectByName[id.recordName] {
                        obj.setValue(CKRecordMapper.encodedSystemFields(of: saved), forKey: "ckSystemFields")
                        obj.setValue(saved.recordID.zoneID.zoneName, forKey: "ckZoneName")
                    }
                case .failure(let e):
                    if let ck = e as? CKError, ck.code == .serverRecordChanged, let server = ck.serverRecord,
                       let obj = objectByName[id.recordName] {
                        CKRecordMapper.applyFields(of: obj, to: server) // client-trumps (LWW)
                        conflicts.append(server)
                    } else {
                        Self.log.error("push record failed: \(e.localizedDescription, privacy: .public)")
                    }
                }
            }
            if !conflicts.isEmpty {
                let (retry, _) = try await db.modifyRecords(saving: conflicts, deleting: [],
                                                            savePolicy: .ifServerRecordUnchanged, atomically: false)
                for (id, result) in retry {
                    if case .success(let saved) = result, let obj = objectByName[id.recordName] {
                        obj.setValue(CKRecordMapper.encodedSystemFields(of: saved), forKey: "ckSystemFields")
                        obj.setValue(saved.recordID.zoneID.zoneName, forKey: "ckZoneName")
                    }
                }
            }
            SharedSyncEngine.applyingRemote = true
            try? ctx.save()
            SharedSyncEngine.applyingRemote = false
        } catch {
            Self.log.error("push batch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run the app build. Expected: BUILD SUCCEEDED, no new warnings in `SharedSyncEngine.swift` (`database(forZone:)` is now used).

- [ ] **Step 3: Regression test**

Run `-only-testing:"Did I Feed The DogTests/SharedSyncEnginePushDecisionTests"` and `-only-testing:"Did I Feed The DogTests/SharedSyncEngineRoutingTests"`. Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedSyncEngine.swift"
git commit -m "feat: route push per zone to private or shared database (#57 phase 3)"
```

---

### Task 6: ShareController + CloudSharingView

**Files:**
- Create: `Did I Feed The Dog/Sharing/ShareController.swift`
- Create: `Did I Feed The Dog/Views/CloudSharingView.swift`

**Interfaces:**
- Consumes: `SharedSyncEngine` (`ensureZone`), `CKRecordMapper.zoneID(forRoot:)`.
- Produces:
  - `@MainActor enum ShareController` with `static func makeShare(forRoot pet: SharedPet) async throws -> CKShare`, `static func fetchShare(forRoot pet: SharedPet) async throws -> CKShare?`, `static func stopSharing(forRoot pet: SharedPet) async`.
  - `struct CloudSharingView: UIViewControllerRepresentable` constructed with a `CKShare`.

- [ ] **Step 1: Implement ShareController**

Create `Did I Feed The Dog/Sharing/ShareController.swift`:

```swift
import CloudKit
import Foundation
import os

/// Owner-side share lifecycle: create a zone-wide CKShare for a shared dog, fetch it back,
/// and stop sharing (delete the zone). Phase 3 operates on DEBUG-seeded SharedPets; the real
/// Pro-gated entry point ships with first-share migration.
@MainActor
enum ShareController {
    private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "ShareController")
    private static let container = CKContainer(identifier: "iCloud.com.delon.DidIFeedTheDog.sharedsync")
    private static var privateDB: CKDatabase { container.privateCloudDatabase }

    /// Ensure the dog's zone exists, then create (or fetch the existing) zone-wide share.
    static func makeShare(forRoot pet: SharedPet) async throws -> CKShare {
        await SharedSyncEngine.shared.ensureZone(forRoot: pet)
        let zoneID = CKRecordMapper.zoneID(forRoot: pet)
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = (pet.name ?? "A dog") as CKRecordValue
        share.publicPermission = .none
        do {
            _ = try await privateDB.modifyRecords(saving: [share], deleting: [], savePolicy: .ifServerRecordUnchanged)
            return share
        } catch let e as CKError where e.code == .serverRecordChanged || e.code == .partialFailure {
            // Already shared (interrupted retry) — fetch the well-known zone-wide share.
            let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            guard let existing = try await privateDB.record(for: id) as? CKShare else { throw e }
            return existing
        }
    }

    static func fetchShare(forRoot pet: SharedPet) async throws -> CKShare? {
        let zoneID = CKRecordMapper.zoneID(forRoot: pet)
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        return try? await privateDB.record(for: id) as? CKShare
    }

    /// Owner stops sharing: delete the zone (participants get zoneNotFound → purge) and clean up locally.
    static func stopSharing(forRoot pet: SharedPet) async {
        let zoneID = CKRecordMapper.zoneID(forRoot: pet)
        do {
            _ = try await privateDB.modifyRecordZones(saving: [], deleting: [zoneID])
        } catch {
            Self.log.error("stopSharing failed: \(error.localizedDescription, privacy: .public)")
        }
        await SharedSyncEngine.shared.purgeLocalZone(named: zoneID.zoneName)
    }
}
```

> This calls `SharedSyncEngine.shared.purgeLocalZone(named:)`. Add a tiny public wrapper to the engine that purges a zone by name on the private scope (so `ShareController` need not duplicate the purge). In `SharedSyncEngine.swift`, add:
> ```swift
>     /// Public entry for owner stop-sharing: purge the local copy of a zone by name.
>     func purgeLocalZone(named zoneName: String) {
>         let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
>         purgeZone(zoneID, scope: "private")
>     }
> ```

- [ ] **Step 2: Implement CloudSharingView**

Create `Did I Feed The Dog/Views/CloudSharingView.swift`:

```swift
import CloudKit
import SwiftUI
import UIKit

/// Presents UICloudSharingController for an already-saved zone-wide CKShare. Locked to
/// read-write participants (no read-only or public toggle).
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    private let container = CKContainer(identifier: "iCloud.com.delon.DidIFeedTheDog.sharedsync")

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}
```

- [ ] **Step 3: Build to verify it compiles**

Run the app build. Expected: BUILD SUCCEEDED. (Verify `CKRecordNameZoneWideShare`, `CKShare.SystemFieldKey.title`, `UICloudSharingController.PermissionOptions` cases against the SDK with the LSP tool if the compiler disagrees.)

- [ ] **Step 4: Commit**

```bash
git add "Did I Feed The Dog/Sharing/ShareController.swift" "Did I Feed The Dog/Views/CloudSharingView.swift" "Did I Feed The Dog/Sharing/SharedSyncEngine.swift"
git commit -m "feat: ShareController (create/fetch/stop) + CloudSharingView (#57 phase 3)"
```

---

### Task 7: Accept invitations in the existing scene delegate

**Files:**
- Modify: `Did I Feed The Dog/Services/QuickActionManager.swift`

**Interfaces:**
- Consumes: `SharedSyncEngine.fetchAllZones`, `SharingFeatureFlag`.
- Produces: `QuickActionSceneDelegate` accepts CloudKit share invitations (cold-launch + running); `Notification.Name.didAcceptShare` posted on success.

- [ ] **Step 1: Add share-acceptance to QuickActionSceneDelegate**

In `Did I Feed The Dog/Services/QuickActionManager.swift`:

Add the notification name near the top (next to `quickActionTriggered`):

```swift
extension Notification.Name {
    static let didAcceptShare = Notification.Name("didAcceptShare")
}
```

Extend `QuickActionSceneDelegate`:
- In `scene(_:willConnectTo:options:)`, after the existing shortcut handling, add cold-launch share acceptance:

```swift
        if let meta = connectionOptions.cloudKitShareMetadata {
            acceptShare(meta)
        }
```

- Add the accept handler + the running-app delegate method to the class:

```swift
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        acceptShare(cloudKitShareMetadata)
    }

    private func acceptShare(_ metadata: CKShare.Metadata) {
        guard SharingFeatureFlag.isFoundationEnabled else { return }
        let container = CKContainer(identifier: "iCloud.com.delon.DidIFeedTheDog.sharedsync")
        let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
        op.acceptSharesResultBlock = { result in
            switch result {
            case .success:
                Task { @MainActor in
                    await SharedSyncEngine.shared.fetchAllZones()
                    NotificationCenter.default.post(name: .didAcceptShare, object: nil)
                }
            case .failure(let error):
                Logger(subsystem: "com.delon.DidIFeedTheDog", category: "ShareAccept")
                    .error("acceptShare failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        container.add(op)
    }
```

Add `import CloudKit` and `import os` to the file's imports (it currently imports SwiftUI + UIKit).

- [ ] **Step 2: Build to verify it compiles**

Run the app build. Expected: BUILD SUCCEEDED. Verify `connectionOptions.cloudKitShareMetadata` (singular) and `CKAcceptSharesOperation.acceptSharesResultBlock` against the SDK with the LSP tool if the compiler disagrees; adapt minimally and note it.

- [ ] **Step 3: Commit**

```bash
git add "Did I Feed The Dog/Services/QuickActionManager.swift"
git commit -m "feat: accept CloudKit share invitations via the scene delegate (#57 phase 3)"
```

---

### Task 8: DEBUG affordances + verification

**Files:**
- Modify: `Did I Feed The Dog/Views/SharedPetCard.swift` (DEBUG Share / Stop-sharing buttons)

**Interfaces:**
- Consumes: `ShareController`, `CloudSharingView`, `SharingFeatureFlag`.

- [ ] **Step 1: Add DEBUG share controls to SharedPetCard**

In `Did I Feed The Dog/Views/SharedPetCard.swift`, the card currently takes `let dog: any DogDisplayable`. Add, under `#if DEBUG`, a context menu (or buttons) that — only when the underlying dog is a `SharedPet` — let the tester share or stop sharing. Read the file first to match its layout. Add state + a `.sheet` for the sharing controller, and a `.contextMenu`:

```swift
#if DEBUG
    @State private var shareToPresent: CKShare?
#endif
```

and on the card's root view:

```swift
#if DEBUG
        .contextMenu {
            if let pet = dog as? SharedPet {
                Button("Share this dog") {
                    Task { shareToPresent = try? await ShareController.makeShare(forRoot: pet) }
                }
                Button("Stop sharing", role: .destructive) {
                    Task { await ShareController.stopSharing(forRoot: pet) }
                }
            }
        }
        .sheet(item: $shareToPresent) { share in
            CloudSharingView(share: share)
        }
#endif
```

> `CKShare` must be `Identifiable` for `.sheet(item:)`. Add, in `CloudSharingView.swift` (or this file) under any scope: `extension CKShare: @retroactive Identifiable { public var id: String { recordID.recordName } }`. If the SDK already conforms `CKShare`/`CKRecord` to `Identifiable`, omit this. Verify with the LSP tool; if a redundant-conformance error appears, drop the extension.

- [ ] **Step 2: Build + full test suite**

Run the app build, then the full suite (single sim):
```
xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 2>&1 | tail -40
```
Expected: BUILD SUCCEEDED; new suites (SyncTokenStoreDBScopeTests, CloudKitIdentityTests, SharedSyncEngineRoutingTests) PASS; no NEW failures in touched files.

- [ ] **Step 3: Confirm flag-off no-op**

Reason about / verify: with `sharingFoundationEnabled` false, `database(forZone:)` is never reached (engine not started), `fetchAllZones`/accept return immediately, and the DEBUG controls are `#if DEBUG` only. Zero CloudKit calls in release.

- [ ] **Step 4: Manual cross-account validation (DEBUG, two DIFFERENT iCloud accounts) — REQUIRED**

Run from the home screen, not Xcode. Account A (owner) and account B (participant), both flag on, sharedsync container provisioned:
1. A: DEBUG-seed a SharedPet → long-press its card → "Share this dog" → invite link sent to B.
2. B: open the link → accept → after a foreground fetch the dog appears on B's dashboard.
3. B edits (DEBUG) → A sees it after a foreground fetch; A edits → B sees it (both-direction routing).
4. A: "Stop sharing" → the dog disappears on B; no resurrection, no loop.
5. Cold-launch B normally (no link) → app opens fine (scene-delegate guard holds).
6. Re-confirm same-account sync (Phase 2) still works (no routing regression).

Record results in the report; this step is run on hardware by the developer.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Views/SharedPetCard.swift"
git commit -m "feat: DEBUG share / stop-sharing controls on shared dog card (#57 phase 3)"
```

---

## Self-Review

**Spec coverage:**
- `CloudKitIdentity` (sharedsync user record name) → Task 2. ✓
- `SyncStateStore` → **dropped (YAGNI)**, documented in Global Constraints; routing covered by `isOwnedZone` + per-DB enumeration. ✓
- `database(forZone:)` routing incl. seeding-window `hasPrivateToken` → Task 3 (pure, unit-tested). ✓
- Two-database pull (private + shared, scope-keyed tokens) → Task 4 (+ Task 1 per-scope DB token). ✓
- Per-zone push routing → Task 5. ✓
- `ShareController` make/fetch/stop + zone-wide CKShare idempotency → Task 6. ✓
- `CloudSharingView` read-write-locked → Task 6. ✓
- Accept via `CKAcceptSharesOperation` in the existing scene delegate (gotcha #5 neutralized) → Task 7. ✓
- DEBUG share/stop affordances → Task 8. ✓
- Flag-off zero-CloudKit + manual cross-account validation → Task 8 Steps 3–4. ✓
- Out-of-scope (silent push, migration, participant leave, attribution) → not implemented. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. CloudKit API-shape verifications are flagged as "confirm against SDK, adapt minimally" with the concrete fallback, not as unfinished work.

**Type consistency:** `isOwnedZone(ownerName:myCloudKitID:hasPrivateToken:)` signature matches Task 3 impl + its tests. `loadDBToken(scope:)/saveDBToken(_:scope:)` (Task 1) used in Task 4. `database(forZone:)` (Task 3) used in Task 5. `SharedSyncEngine.shared.ensureZone`/`purgeLocalZone` used by `ShareController` (Task 6, wrapper added same task). `CloudKitIdentity.shared.cachedID` (Task 2) used in Task 3. `Notification.Name.didAcceptShare` defined + posted in Task 7. `CloudSharingView(share:)` (Task 6) used in Task 8. `ShareController.makeShare/stopSharing` (Task 6) used in Task 8.
