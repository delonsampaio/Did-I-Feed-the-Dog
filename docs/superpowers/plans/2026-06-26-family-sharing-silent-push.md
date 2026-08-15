# Family Sharing — Phase 4 Silent Push Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wake the app in the background via silent CloudKit push (two `CKDatabaseSubscription`s + APNs) and run the existing `fetchAllZones()`, so shared-dog changes appear within seconds instead of waiting for the poll.

**Architecture:** No new sync logic. Add the Push Notifications capability, a `SharedSyncPushSubscriptions` helper that saves one silent subscription to the sharedsync private DB and one to its shared DB (idempotent), APNs registration + a silent-push handler in the existing `QuickActionAppDelegate` that routes our pushes to `SharedSyncEngine.shared.fetchAllZones()`, and lengthen the foreground poll to 75s as a backstop. All behind `SharingFeatureFlag.isFoundationEnabled`.

**Tech Stack:** Swift, CloudKit (`CKDatabaseSubscription`, `CKSubscription.NotificationInfo`, `CKNotification`), UIKit (`UIApplicationDelegate` remote-notification methods), XCTest.

**Spec:** `docs/superpowers/specs/2026-06-26-family-sharing-silent-push-design.md`

## Global Constraints

- **Container:** `iCloud.com.delon.DidIFeedTheDog.sharedsync`. Subscribe to its `privateCloudDatabase` (owner wakes on participant edits) AND its `sharedCloudDatabase` (participant wakes on owner edits).
- **Flag-gated:** APNs registration, subscription creation, and push handling run ONLY when `SharingFeatureFlag.isFoundationEnabled`. Flag off ⇒ no registration, no subscriptions, handler returns `.noData` immediately — behavior identical to today.
- **Silent only:** `notificationInfo.shouldSendContentAvailable = true`; no alert/badge/sound. No user-visible notifications this phase.
- **Subscription IDs (fixed):** `"sharedsync-private-db"` and `"sharedsync-shared-db"`.
- **Register-once guard:** UserDefaults key `"sharedSyncSubscriptionsRegistered"`; on save failure, leave/clear it false so the next launch retries.
- **`aps-environment`:** `development` for dev/device testing. **Release/TestFlight/App Store requires `production`** — RELEASE CHECKLIST ITEM, documented, not a code concern this phase. `remote-notification` background mode is ALREADY in the app Info.plist (do not re-add).
- **No NSPCKC / no NSPersistentCloudKitContainer subscription trick** — plain `CKDatabaseSubscription` with our own IDs.
- **Never `fatalError`.** Log via `os.Logger(subsystem: "com.delon.DidIFeedTheDog", category: ...)`.

### Environment / mechanics (every task)

- New files → `Did I Feed The Dog/Sharing/`; tests → `Did I Feed The DogTests/`. Xcode 16 filesystem-synchronized groups — **no `project.pbxproj` edits**.
- **Swift 6 `-default-isolation=MainActor` strict concurrency.** Mark pure `static` helpers accessed from nonisolated contexts `nonisolated`. The push handler's `@escaping` completion is captured into a `Task { @MainActor in … }` — keep the capture minimal.
- **Single simulator (limited RAM — never parallel clones).** Test:
  ```
  xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:"Did I Feed The DogTests/<ClassName>" 2>&1 | tail -40
  ```
  Build:
  ```
  xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
  ```
- **Known-flaky/environmental baseline:** several suites (AppSettings/FeedingEvent/FeedingLogService/LoggedBy/PetTests) fail in the sandbox due to App-Group store read-only + no iCloud account — NOT ours. Judge success by new tests passing + no NEW failures in touched files.
- **Silent push cannot be tested on the simulator** — the push path is validated on a real device (Task 3 manual checklist). Unit tests cover only the pure helpers.
- Verify CloudKit/UIKit API shapes against the SDK (LSP or header grep) before relying on memory; adapt minimally + note.

---

### Task 1: aps-environment entitlement

**Files:**
- Modify: `DidIFeedTheDog.entitlements`

**Interfaces:**
- Produces: the app target requests APNs (`aps-environment = development`).

- [ ] **Step 1: Add the key**

In `DidIFeedTheDog.entitlements`, add inside the top-level `<dict>` (e.g. after the `icloud-services` array):

```xml
	<key>aps-environment</key>
	<string>development</string>
```

- [ ] **Step 2: Verify the app builds**

Run the app build. Expected: BUILD SUCCEEDED. (A local signing note about push is acceptable; the developer enables the Push Notifications capability / regenerates the profile before device testing. **Release archives must use `production`** — this is a documented release checklist item, not changed here.)

- [ ] **Step 3: Commit**

```bash
git add DidIFeedTheDog.entitlements
git commit -m "chore: add aps-environment (development) for silent push (#57 phase 4)"
```

---

### Task 2: SharedSyncPushSubscriptions

**Files:**
- Create: `Did I Feed The Dog/Sharing/SharedSyncPushSubscriptions.swift`
- Test: `Did I Feed The DogTests/SharedSyncPushSubscriptionsTests.swift`

**Interfaces:**
- Consumes: `SharingFeatureFlag`, `CKContainer`.
- Produces:
  - `@MainActor final class SharedSyncPushSubscriptions` with `static let shared`, `init(defaults:)`, `func registerIfNeeded() async`.
  - `nonisolated static let privateSubID = "sharedsync-private-db"`, `nonisolated static let sharedSubID = "sharedsync-shared-db"`.
  - `nonisolated static func isOurSharedSyncNotification(subscriptionID: String?) -> Bool`.
  - `nonisolated static func shouldAttemptRegistration(flagEnabled: Bool, alreadyRegistered: Bool) -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `Did I Feed The DogTests/SharedSyncPushSubscriptionsTests.swift`:

```swift
import XCTest
@testable import Did_I_Feed_The_Dog

final class SharedSyncPushSubscriptionsTests: XCTestCase {

    func testIsOurNotificationMatchesBothSubscriptionIDs() {
        XCTAssertTrue(SharedSyncPushSubscriptions.isOurSharedSyncNotification(
            subscriptionID: SharedSyncPushSubscriptions.privateSubID))
        XCTAssertTrue(SharedSyncPushSubscriptions.isOurSharedSyncNotification(
            subscriptionID: SharedSyncPushSubscriptions.sharedSubID))
    }

    func testIsOurNotificationRejectsForeignAndNil() {
        XCTAssertFalse(SharedSyncPushSubscriptions.isOurSharedSyncNotification(subscriptionID: "some-other-sub"))
        XCTAssertFalse(SharedSyncPushSubscriptions.isOurSharedSyncNotification(subscriptionID: nil))
    }

    func testShouldAttemptRegistrationOnlyWhenFlagOnAndNotYetRegistered() {
        XCTAssertTrue(SharedSyncPushSubscriptions.shouldAttemptRegistration(flagEnabled: true, alreadyRegistered: false))
        XCTAssertFalse(SharedSyncPushSubscriptions.shouldAttemptRegistration(flagEnabled: true, alreadyRegistered: true))
        XCTAssertFalse(SharedSyncPushSubscriptions.shouldAttemptRegistration(flagEnabled: false, alreadyRegistered: false))
        XCTAssertFalse(SharedSyncPushSubscriptions.shouldAttemptRegistration(flagEnabled: false, alreadyRegistered: true))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `-only-testing:"Did I Feed The DogTests/SharedSyncPushSubscriptionsTests"`. Expected: compile failure (`SharedSyncPushSubscriptions` undefined).

- [ ] **Step 3: Implement**

Create `Did I Feed The Dog/Sharing/SharedSyncPushSubscriptions.swift`:

```swift
import CloudKit
import Foundation
import os

/// Registers silent CloudKit database subscriptions so the app is woken by APNs when a shared
/// dog changes. Two subscriptions: one on the sharedsync private DB (owner wakes on participant
/// edits) and one on its shared DB (participant wakes on owner edits). No NSPCKC involved, so
/// these are plain CKDatabaseSubscriptions with our own IDs and content-available delivery.
@MainActor
final class SharedSyncPushSubscriptions {
    static let shared = SharedSyncPushSubscriptions()

    nonisolated static let privateSubID = "sharedsync-private-db"
    nonisolated static let sharedSubID = "sharedsync-shared-db"

    nonisolated private static let log = Logger(subsystem: "com.delon.DidIFeedTheDog", category: "SharedSyncPush")
    nonisolated private static let registeredKey = "sharedSyncSubscriptionsRegistered"

    private let container = CKContainer(identifier: "iCloud.com.delon.DidIFeedTheDog.sharedsync")
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Is this incoming CloudKit notification for one of our two subscriptions?
    nonisolated static func isOurSharedSyncNotification(subscriptionID: String?) -> Bool {
        guard let subscriptionID else { return false }
        return subscriptionID == privateSubID || subscriptionID == sharedSubID
    }

    /// Pure guard: attempt registration only when sharing is on and we haven't succeeded before.
    nonisolated static func shouldAttemptRegistration(flagEnabled: Bool, alreadyRegistered: Bool) -> Bool {
        flagEnabled && !alreadyRegistered
    }

    /// Save both subscriptions once. Idempotent: a UserDefaults flag prevents re-saving every
    /// launch; a failure clears the flag so the next launch retries. No-op unless the flag is on.
    func registerIfNeeded() async {
        let alreadyRegistered = defaults.bool(forKey: Self.registeredKey)
        guard Self.shouldAttemptRegistration(flagEnabled: SharingFeatureFlag.isFoundationEnabled,
                                             alreadyRegistered: alreadyRegistered) else { return }
        do {
            try await save(Self.privateSubID, to: container.privateCloudDatabase)
            try await save(Self.sharedSubID, to: container.sharedCloudDatabase)
            defaults.set(true, forKey: Self.registeredKey)
        } catch {
            defaults.set(false, forKey: Self.registeredKey) // retry on next launch
            Self.log.error("subscription registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save(_ id: String, to db: CKDatabase) async throws {
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true // silent: no alert/badge/sound
        subscription.notificationInfo = info
        _ = try await db.modifySubscriptions(saving: [subscription], deleting: [])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run `-only-testing:"Did I Feed The DogTests/SharedSyncPushSubscriptionsTests"`. Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add "Did I Feed The Dog/Sharing/SharedSyncPushSubscriptions.swift" "Did I Feed The DogTests/SharedSyncPushSubscriptionsTests.swift"
git commit -m "feat: SharedSyncPushSubscriptions (two silent CKDatabaseSubscriptions) (#57 phase 4)"
```

---

### Task 3: APNs registration + push handler + wiring + poll

**Files:**
- Modify: `Did I Feed The Dog/Services/QuickActionManager.swift` (`QuickActionAppDelegate`)
- Modify: `Did I Feed The Dog/Sharing/SharedSyncEngine.swift` (kick `registerIfNeeded` from `start()`)
- Modify: `Did I Feed The Dog/Did_I_Feed_The_Dog_App.swift` (poll 20s → 75s)

**Interfaces:**
- Consumes: `SharedSyncPushSubscriptions` (Task 2), `SharedSyncEngine.shared.fetchAllZones`, `SharingFeatureFlag`.
- Produces: the app registers for remote notifications (flag-gated), routes our silent pushes to `fetchAllZones()`, registers the subscriptions on engine start, and polls every 75s.

- [ ] **Step 1: Add registration + push handling to QuickActionAppDelegate**

In `Did I Feed The Dog/Services/QuickActionManager.swift`, add `import CloudKit` and `import os` if not present. Extend `QuickActionAppDelegate` (which currently only has `configurationForConnecting`) with:

```swift
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if SharingFeatureFlag.isFoundationEnabled {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // CloudKit uses the APNs token server-side; nothing to forward. Log for diagnostics.
        Logger(subsystem: "com.delon.DidIFeedTheDog", category: "SharedSyncPush")
            .info("registered for remote notifications")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger(subsystem: "com.delon.DidIFeedTheDog", category: "SharedSyncPush")
            .error("remote notification registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard SharingFeatureFlag.isFoundationEnabled else { completionHandler(.noData); return }
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard SharedSyncPushSubscriptions.isOurSharedSyncNotification(subscriptionID: notification?.subscriptionID) else {
            completionHandler(.noData); return
        }
        Task { @MainActor in
            await SharedSyncEngine.shared.fetchAllZones()
            completionHandler(.newData)
        }
    }
```

> If the compiler flags the `@escaping` completion capture under strict concurrency (non-Sendable across the `Task`), wrap the final call as `Task { @MainActor in await SharedSyncEngine.shared.fetchAllZones(); await MainActor.run { completionHandler(.newData) } }` or mark the closure capture explicitly — keep behavior identical (always call the completion exactly once). Note any adaptation.

- [ ] **Step 2: Kick subscription registration from engine start**

In `Did I Feed The Dog/Sharing/SharedSyncEngine.swift`, in `start()` (currently: guard flag; attach observer; `Task { await fetchAllZones() }`), add a second Task so registration runs alongside the initial fetch:

```swift
    func start() {
        guard SharingFeatureFlag.isFoundationEnabled else { return }
        if !startedObserving { attachPushObserver(); startedObserving = true }
        Task { await fetchAllZones() }
        Task { await SharedSyncPushSubscriptions.shared.registerIfNeeded() }
    }
```

- [ ] **Step 3: Lengthen the foreground poll to 75s**

In `Did I Feed The Dog/Did_I_Feed_The_Dog_App.swift`, the poll loop sleeps `Task.sleep(for: .seconds(20))`. Change it to:

```swift
                        try? await Task.sleep(for: .seconds(75))
```

(Only the interval changes; launch fetch and `scenePhase == .active` fetch are unchanged.)

- [ ] **Step 4: Build + full test suite**

Run the app build, then the full suite (single sim):
```
xcodebuild build -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
xcodebuild test -project "Did I Feed The Dog.xcodeproj" -scheme "Did I Feed The Dog" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 2>&1 | tail -40
```
Expected: BUILD SUCCEEDED; `SharedSyncPushSubscriptionsTests` PASS + all prior new suites PASS; no NEW failures in touched files (the environmental baseline failures are unchanged).

- [ ] **Step 5: Confirm flag-off no-op**

Reason about / verify: with `sharingFoundationEnabled` false — `didFinishLaunching` skips `registerForRemoteNotifications`; `didReceiveRemoteNotification` returns `.noData` immediately; `SharedSyncEngine.start()` returns before the registration Task; the poll guard fails. Zero APNs/CloudKit activity in release.

- [ ] **Step 6: Manual real-device validation (REQUIRED) — silent push does NOT work on the simulator**

On two real devices with two iCloud accounts, both flag on, sharedsync container provisioned, launched from the home screen (not Xcode — the debugger masks push):
1. Share a dog A→B (Phase 3 DEBUG flow) so B has the shared dog.
2. Background B's app. Edit the dog on A.
3. Within seconds, B applies the change (verify by foregrounding B — it's already current, not fetching on open), confirming the silent push woke it.
4. With the flag OFF, confirm no subscription is created and no push is requested (and sharing UI is hidden).
5. Confirm Phases 2–3 sync (launch/foreground/poll, cross-account) still work.

Record results in the report; this step is run on hardware by the developer.

- [ ] **Step 7: Commit**

```bash
git add "Did I Feed The Dog/Services/QuickActionManager.swift" "Did I Feed The Dog/Sharing/SharedSyncEngine.swift" "Did I Feed The Dog/Did_I_Feed_The_Dog_App.swift"
git commit -m "feat: APNs registration + silent-push handler + 75s poll backstop (#57 phase 4)"
```

---

## Self-Review

**Spec coverage:**
- `aps-environment` capability (dev; production release note) → Task 1. ✓
- `SharedSyncPushSubscriptions` (two silent DB subscriptions, register-once guard, `isOurSharedSyncNotification`) → Task 2. ✓
- APNs registration + `didRegister/didFail` logs + `didReceiveRemoteNotification` → fetchAllZones, flag-gated → Task 3 Step 1. ✓
- Registration wired into `SharedSyncEngine.start()` → Task 3 Step 2. ✓
- Poll 20s → 75s → Task 3 Step 3. ✓
- Flag-off zero-activity + real-device manual validation → Task 3 Steps 5–6. ✓
- Out-of-scope (migration, Share button, leave, attribution, alerting notifications) → not implemented. ✓
- `remote-notification` background mode already present → not re-added (noted in Global Constraints). ✓

**Placeholder scan:** No TBD/TODO; all code steps complete. The one concurrency caveat (escaping completion across `Task`) has a concrete fallback, not a placeholder.

**Type consistency:** `SharedSyncPushSubscriptions.isOurSharedSyncNotification(subscriptionID:)`, `.privateSubID`/`.sharedSubID`, `.shouldAttemptRegistration(flagEnabled:alreadyRegistered:)`, `.shared.registerIfNeeded()` — signatures match between Task 2 impl, its tests, and Task 3 consumers. `SharedSyncEngine.shared.fetchAllZones()` / `.start()` match Phase 2/3. Poll edit targets the existing `Task.sleep(for: .seconds(20))` line.
